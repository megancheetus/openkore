@echo off
echo [*] Redirecionando faixa LATAM para IP spoofado...

route add 172.65.0.0 mask 255.255.0.0 172.65.175.75

echo [*] Pronto. Pressione qualquer tecla para sair.
pause >nul