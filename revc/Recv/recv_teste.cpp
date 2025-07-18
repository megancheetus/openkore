// File contributed by #Francisco Wallison, #megafuji, #gaaradodesertoo, originally by #__codeplay

// =================================================================================================
// recv.cpp - Hook para o recv do Openkore 
// Meu trabalho pessoal de melhoria da dll usada para hookar o recv do Openkore.
// Este código é uma versão melhorada do recv.cpp original, que implementa melhorias significativas 
// manté-mse a lógica de pacotes, mas corrigindo:
// 1. O loop infinito que travava o sistema.
// 2. O vazamento de memória com o uso de smart pointers (unique_ptr).
// 3. O uso de buffers de rede para segurança de dados (vector<char>).
// =================================================================================================

#define WIN32_LEAN_AND_MEAN
#define _WINSOCK_DEPRECATED_NO_WARNINGS

#include <winsock2.h>
#include <windows.h>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <fstream>
#include <unordered_map>
#include <algorithm>
#include <cstring>
#include <vector>
#include <memory>

#pragma comment(lib, "ws2_32.lib")

// --- Estruturas e Tipos ---
struct Packet {
	char ID;
	unsigned short len;
	char* data;
};
struct PacketDeleter {
	void operator()(Packet* p) const {
		if (p) {
			delete[] p->data;
			delete p;
		}
	}
};
typedef int (WINAPI* recv_func_t)(SOCKET s, char* buf, int len, int flags);
recv_func_t original_recv = nullptr;
typedef int(__thiscall* SendToClientFunc)(void* CragConnection, size_t size, char* buffer);
SendToClientFunc sendFunc;
typedef void* (__stdcall* originalInstanceR)(void);
originalInstanceR instanceR;
enum e_PacketType {
	RECEIVED = 0,
	SENDED = 1
};

// --- Variáveis Globais ---
DWORD clientSubAddress, CRagConnection_instanceR_address, recvPtrAddress, koreServerPort;
std::string koreServerIP, applyHookKey, removeHookKey;
bool applyHookRequiresCtrl = false, applyHookRequiresShift = false;
bool removeHookRequiresCtrl = false, removeHookRequiresShift = false;
int applyHookVK = VK_F11, removeHookVK = VK_F12;
bool allowMultiClient = false;
bool hook_applied = false, koreClientIsAlive = false, keepMainThread = true;
HANDLE hThread;
SOCKET koreClient = INVALID_SOCKET;
SOCKET roServer = INVALID_SOCKET;
std::vector<char> xkoreSendBuf;
bool imalive = false;

// --- Constantes ---
#define BUF_SIZE             1024 * 32
#define TIMEOUT              600000
#define RECONNECT_INTERVAL   3000
#define PING_INTERVAL        5000
#define SLEEP_TIME           10
#define SF_CLOSED            -1

// --- Protótipos das Funções ---
DWORD WINAPI KeyboardMonitorThread(LPVOID lpParam);
DWORD WINAPI koreConnectionMain(LPVOID lpParam);
bool isConnected(SOCKET s);
SOCKET createSocket(const std::string& ip, int port);
int readSocket(SOCKET s, char* buf, int len);
std::unique_ptr<Packet, PacketDeleter> unpackPacket(const char* buf, size_t buflen, size_t& next);
void processPacket(Packet* packet);
void AllocateConsole();
bool LoadConfig(const std::string& filename);
bool ApplyHook();
void RemoveHook();
void init();
void finish();
bool CreateDefaultConfig(const std::string& filename);
int ParseKeyString(const std::string& keyStr, bool& requiresCtrl, bool& requiresShift);
DWORD GetUserPort();

// --- Implementações ---

void sendDataToKore(char* buffer, int len, e_PacketType type) {
	if (koreClientIsAlive) {
		std::vector<char> newbuf;
		newbuf.reserve(len + 3);
		unsigned short sLen = static_cast<unsigned short>(len);

		if (type == e_PacketType::RECEIVED) {
			newbuf.push_back('R');
		}
		else {
			newbuf.push_back('S');
		}

		newbuf.insert(newbuf.end(), reinterpret_cast<char*>(&sLen), reinterpret_cast<char*>(&sLen) + 2);
		newbuf.insert(newbuf.end(), buffer, buffer + len);

		xkoreSendBuf.insert(xkoreSendBuf.end(), newbuf.begin(), newbuf.end());
	}
}

int WINAPI hooked_recv(SOCKET s, char* buf, int len, int flags) {
	if (!original_recv) return -1;

	int result = original_recv(s, buf, len, flags);

	if (result > 0) {
		roServer = s;
		sendDataToKore(buf, result, e_PacketType::RECEIVED);
	}
	return result;
}

std::unique_ptr<Packet, PacketDeleter> unpackPacket(const char* buf, size_t buflen, size_t& next) {
	if (buflen < 3) return nullptr;

	unsigned short len = *reinterpret_cast<const unsigned short*>(buf + 1);

	if (buflen < (size_t)(3 + len)) return nullptr;

	Packet* packet = new Packet();
	packet->ID = buf[0];
	packet->len = len;
	packet->data = new char[len];
	memcpy(packet->data, buf + 3, len);

	next = 3 + len;
	return std::unique_ptr<Packet, PacketDeleter>(packet, PacketDeleter());
}

void processPacket(Packet* packet) {
	sendFunc = (SendToClientFunc)(clientSubAddress);
	instanceR = (originalInstanceR)(CRagConnection_instanceR_address);
	switch (packet->ID) {
	case 'S':
		if (roServer != INVALID_SOCKET && isConnected(roServer)) {
			sendFunc(instanceR(), packet->len, packet->data);
		}
		break;
	case 'R':
	case 'K':
	default:
		break;
	}
}

DWORD WINAPI koreConnectionMain(LPVOID lpParam) {
	char buf[BUF_SIZE + 1];
	char pingPacket[3];
	unsigned short pingPacketLength = 0;
	DWORD koreClientTimeout, koreClientPingTimeout, reconnectTimeout;
	std::vector<char> koreClientRecvBuf;

	koreClientTimeout = GetTickCount();
	koreClientPingTimeout = GetTickCount();
	reconnectTimeout = 0;
	memcpy(pingPacket, "K", 1);
	memcpy(pingPacket + 1, &pingPacketLength, 2);

	bool waitingPrinted = false;

	while (keepMainThread) {
		bool isAlive = koreClientIsAlive;
		bool isAliveChanged = false;

		if ((!isAlive || !isConnected(koreClient)) && !waitingPrinted) {
			std::cout << "\n- Se voce ja aplicou o hook (" << applyHookKey << "), abra o Openkore." << std::endl;
			waitingPrinted = true;
		}

		if ((!isAlive || !isConnected(koreClient) || GetTickCount() - koreClientTimeout > TIMEOUT)
			&& GetTickCount() - reconnectTimeout > RECONNECT_INTERVAL) {

			if (koreClient != INVALID_SOCKET) {
				closesocket(koreClient);
			}
			koreClient = createSocket(koreServerIP, koreServerPort);

			isAlive = koreClient != INVALID_SOCKET;
			isAliveChanged = true;
			if (isAlive) {
				koreClientTimeout = GetTickCount();
				waitingPrinted = false;
			}
			reconnectTimeout = GetTickCount();
		}

		if (isAlive) {
			if (!imalive) {
				imalive = true;
			}

			int ret = readSocket(koreClient, buf, BUF_SIZE);
			if (ret == SF_CLOSED) {
				closesocket(koreClient);
				koreClient = INVALID_SOCKET;
				isAlive = false;
				isAliveChanged = true;
				imalive = false;
			}
			else if (ret > 0) {
				size_t next = 0;
				size_t total_processed = 0;
				koreClientRecvBuf.insert(koreClientRecvBuf.end(), buf, buf + ret);

				const char* recvData = koreClientRecvBuf.data();
				size_t recvSize = koreClientRecvBuf.size();

				while (auto packet = unpackPacket(recvData + total_processed, recvSize - total_processed, next)) {
					processPacket(packet.get());
					total_processed += next;
				}
				if (total_processed > 0) {
					koreClientRecvBuf.erase(koreClientRecvBuf.begin(), koreClientRecvBuf.begin() + total_processed);
				}

				koreClientTimeout = GetTickCount();
			}
		}

		if (!xkoreSendBuf.empty()) {
			if (isAlive) {
				send(koreClient, xkoreSendBuf.data(), static_cast<int>(xkoreSendBuf.size()), 0);
			}
			else {
				size_t next;
				size_t total_processed = 0;
				const char* sendData = xkoreSendBuf.data();
				size_t sendSize = xkoreSendBuf.size();

				while (auto packet = unpackPacket(sendData + total_processed, sendSize - total_processed, next)) {
					if (packet->ID == 'S')
						send(roServer, packet->data, packet->len, 0);
					total_processed += next;
				}
				if (total_processed > 0) {
					xkoreSendBuf.erase(xkoreSendBuf.begin(), xkoreSendBuf.begin() + total_processed);
				}
			}
			if (isAlive) {
				xkoreSendBuf.clear();
			}
		}

		if (koreClientIsAlive && GetTickCount() - koreClientPingTimeout > PING_INTERVAL) {
			send(koreClient, pingPacket, 3, 0);
			koreClientPingTimeout = GetTickCount();
		}

		if (isAliveChanged) {
			koreClientIsAlive = isAlive;
		}

		Sleep(SLEEP_TIME);
	}
	return 0;
}

void AllocateConsole() {
	AllocConsole();
	FILE* fp;
	freopen_s(&fp, "CONOUT$", "w", stdout);
	freopen_s(&fp, "CONOUT$", "w", stderr);
	freopen_s(&fp, "CONIN$", "r", stdin);
	SetConsoleTitleA("Console de Depuracao");
}

bool ApplyHook() {
	if (IsBadReadPtr((void*)recvPtrAddress, sizeof(DWORD))) {
		std::cout << "[ERRO] Endereco de hook invalido." << std::endl;
		return false;
	}
	original_recv = *(recv_func_t*)recvPtrAddress;
	if (original_recv == nullptr) {
		std::cout << "[ERRO] Ponteiro original eh nulo." << std::endl;
		return false;
	}
	*(recv_func_t*)recvPtrAddress = hooked_recv;
	if (*(recv_func_t*)recvPtrAddress != hooked_recv) {
		std::cout << "[ERRO] Falha ao aplicar hook." << std::endl;
		return false;
	}
	hook_applied = true;
	std::cout << "[INFO] Hook aplicado." << std::endl;
	return true;
}

void RemoveHook() {
	if (original_recv) {
		*(recv_func_t*)recvPtrAddress = original_recv;
		std::cout << "[INFO] Hook removido." << std::endl;
	}
	hook_applied = false;
}

bool isConnected(SOCKET s) {
	if (s == INVALID_SOCKET) return false;
	fd_set readfds;
	FD_ZERO(&readfds);
	FD_SET(s, &readfds);
	timeval timeout = { 0, 0 };
	int result = select(0, &readfds, NULL, NULL, &timeout);
	return result != SOCKET_ERROR;
}

SOCKET createSocket(const std::string& ip, int port) {
	sockaddr_in addr;
	SOCKET sock;
	DWORD arg = 1;
	sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock == INVALID_SOCKET) return INVALID_SOCKET;
	ioctlsocket(sock, FIONBIO, &arg);
	addr.sin_family = AF_INET;
	addr.sin_port = htons(static_cast<u_short>(port));
	addr.sin_addr.s_addr = inet_addr(ip.c_str());
	while (connect(sock, (struct sockaddr*)&addr, sizeof(sockaddr_in)) == SOCKET_ERROR) {
		if (WSAGetLastError() == WSAEISCONN) break;
		else if (WSAGetLastError() != WSAEWOULDBLOCK) {
			closesocket(sock);
			return INVALID_SOCKET;
		}
		else Sleep(10);
	}
	arg = 0;
	ioctlsocket(sock, FIONBIO, &arg);
	return sock;
}

int readSocket(SOCKET s, char* buf, int len) {
	fd_set readfds;
	FD_ZERO(&readfds);
	FD_SET(s, &readfds);
	timeval timeout = { 0, 0 };
	int result = select(0, &readfds, NULL, NULL, &timeout);
	if (result == SOCKET_ERROR) return SF_CLOSED;
	if (result == 0) return 0;
	int bytes = recv(s, buf, len, 0);
	if (bytes == 0 || bytes == SOCKET_ERROR) return SF_CLOSED;
	return bytes;
}

DWORD WINAPI KeyboardMonitorThread(LPVOID lpParam) {
	while (keepMainThread) {
		bool applyKeyPressed = (GetAsyncKeyState(applyHookVK) & 0x8000) != 0;
		bool applyCtrlOk = !applyHookRequiresCtrl || (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
		bool applyShiftOk = !applyHookRequiresShift || (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
		if (applyKeyPressed && applyCtrlOk && applyShiftOk) {
			if (!hook_applied) {
				ApplyHook();
			}
			Sleep(500);
		}

		bool removeKeyPressed = (GetAsyncKeyState(removeHookVK) & 0x8000) != 0;
		bool removeCtrlOk = !removeHookRequiresCtrl || (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
		bool removeShiftOk = !removeHookRequiresShift || (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
		if (removeKeyPressed && removeCtrlOk && removeShiftOk) {
			if (hook_applied) {
				RemoveHook();
			}
			Sleep(500);
		}
		Sleep(100);
	}
	return 0;
}

void init() {
	AllocateConsole();
	if (!LoadConfig("config_recv.txt")) {
		keepMainThread = false;
		return;
	}
	if (allowMultiClient) {
		koreServerPort = GetUserPort();
	}
	WSADATA wsaData;
	WSAStartup(MAKEWORD(2, 2), &wsaData);
	CreateThread(NULL, 0, KeyboardMonitorThread, NULL, 0, NULL);
	hThread = CreateThread(NULL, 0, koreConnectionMain, NULL, 0, NULL);
}

void finish() {
	keepMainThread = false;
	if (hook_applied) {
		RemoveHook();
	}
	if (koreClient != INVALID_SOCKET) {
		closesocket(koreClient);
	}
	WSACleanup();
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
	switch (ul_reason_for_call) {
	case DLL_PROCESS_ATTACH:
		init();
		break;
	case DLL_PROCESS_DETACH:
		finish();
		break;
	}
	return TRUE;
}

bool CreateDefaultConfig(const std::string& filename) {
	std::ofstream fout(filename);
	if (!fout.is_open()) return false;
	fout << "clientSubAddress=B7EF50\n";
	fout << "instanceRAddress=B7F4B0\n";
	fout << "recvPtrAddress=1455BB8\n";
	fout << "koreServerIP=127.0.0.1\n";
	fout << "koreServerPort=2350\n";
	fout << "applyHookKey=Ctrl+F11\n";
	fout << "removeHookKey=Ctrl+F12\n";
	fout << "allowMultiClient=true\n";
	fout.close();
	return true;
}

int ParseKeyString(const std::string& keyStr, bool& requiresCtrl, bool& requiresShift) {
	std::string key = keyStr;
	requiresCtrl = false;
	requiresShift = false;
	std::transform(key.begin(), key.end(), key.begin(), ::toupper);

	if (key.find("CTRL+SHIFT+") == 0 || key.find("SHIFT+CTRL+") == 0) {
		requiresCtrl = true;
		requiresShift = true;
		key = key.substr(11);
	}
	else if (key.find("CTRL+") == 0) {
		requiresCtrl = true;
		key = key.substr(5);
	}
	else if (key.find("SHIFT+") == 0) {
		requiresShift = true;
		key = key.substr(6);
	}

	if (key.length() == 1) {
		char c = key[0];
		if (c >= 'A' && c <= 'Z') return c;
		if (c >= '0' && c <= '9') return c;
	}

	if (key == "F1") return VK_F1;
	if (key == "F2") return VK_F2;
	if (key == "F3") return VK_F3;
	if (key == "F4") return VK_F4;
	if (key == "F5") return VK_F5;
	if (key == "F6") return VK_F6;
	if (key == "F7") return VK_F7;
	if (key == "F8") return VK_F8;
	if (key == "F9") return VK_F9;
	if (key == "F10") return VK_F10;
	if (key == "F11") return VK_F11;
	if (key == "F12") return VK_F12;
	if (key == "ESC") return VK_ESCAPE;
	if (key == "SPACE") return VK_SPACE;
	if (key == "ENTER") return VK_RETURN;
	if (key == "TAB") return VK_TAB;
	if (key == "INSERT") return VK_INSERT;
	if (key == "DELETE") return VK_DELETE;
	if (key == "HOME") return VK_HOME;
	if (key == "END") return VK_END;
	if (key == "PAGEUP") return VK_PRIOR;
	if (key == "PAGEDOWN") return VK_NEXT;
	if (key == "LEFT") return VK_LEFT;
	if (key == "RIGHT") return VK_RIGHT;
	if (key == "UP") return VK_UP;
	if (key == "DOWN") return VK_DOWN;

	return VK_F11;
}

DWORD GetUserPort() {
	char input[256];
	std::cout << "\n[MODO MULTI-CLIENTE]\nDigite a porta do servidor xKore (padrao: " << koreServerPort << "): ";
	if (fgets(input, sizeof(input), stdin)) {
		input[strcspn(input, "\r\n")] = 0;
		if (strlen(input) == 0) {
			return koreServerPort;
		}
		int inputPort = atoi(input);
		if (inputPort > 0 && inputPort <= 65535) {
			return static_cast<DWORD>(inputPort);
		}
	}
	return koreServerPort;
}

bool LoadConfig(const std::string& filename) {
	std::ifstream fin(filename);
	if (!fin.is_open()) {
		CreateDefaultConfig(filename);
		return false;
	}

	std::unordered_map<std::string, std::string> mapa;
	std::string line;
	while (std::getline(fin, line)) {
		if (line.empty() || line[0] == '#') continue;
		size_t pos = line.find('=');
		if (pos == std::string::npos) continue;

		std::string chave = line.substr(0, pos);
		std::string valor = line.substr(pos + 1);

		// Trim whitespace
		chave.erase(chave.find_last_not_of(" \t\r\n") + 1);
		valor.erase(0, valor.find_first_not_of(" \t\r\n"));

		mapa[chave] = valor;
	}
	fin.close();

	try {
		clientSubAddress = std::stoul(mapa.at("clientSubAddress"), nullptr, 16);
		CRagConnection_instanceR_address = std::stoul(mapa.at("instanceRAddress"), nullptr, 16);
		recvPtrAddress = std::stoul(mapa.at("recvPtrAddress"), nullptr, 16);
		koreServerIP = mapa.at("koreServerIP");
		koreServerPort = std::stoul(mapa.at("koreServerPort"));
		applyHookKey = mapa.count("applyHookKey") ? mapa.at("applyHookKey") : "Ctrl+F11";
		removeHookKey = mapa.count("removeHookKey") ? mapa.at("removeHookKey") : "Ctrl+F12";
		applyHookVK = ParseKeyString(applyHookKey, applyHookRequiresCtrl, applyHookRequiresShift);
		removeHookVK = ParseKeyString(removeHookKey, removeHookRequiresCtrl, removeHookRequiresShift);
		if (mapa.count("allowMultiClient")) {
			std::string allowMultiStr = mapa.at("allowMultiClient");
			std::transform(allowMultiStr.begin(), allowMultiStr.end(), allowMultiStr.begin(), ::tolower);
			allowMultiClient = (allowMultiStr == "true" || allowMultiStr == "1" || allowMultiStr == "yes");
		}
	}
	catch (const std::exception& e) {
		// CORREÇÃO PARA O WARNING C4101
		std::cout << "[ERRO] Falha ao ler configuracao: " << e.what() << std::endl;
		return false;
	}
	return true;
}
