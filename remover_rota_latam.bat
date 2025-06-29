@echo off
echo [*] Removendo rota da faixa LATAM (172.65.0.0/16)...

route delete 172.65.0.0

echo [*] Rota removida com sucesso. Pressione qualquer tecla para sair.
pause >nul