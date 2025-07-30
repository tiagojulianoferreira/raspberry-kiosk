#!/bin/bash

# ============================================
#               CONFIGURAÇÕES
# ============================================

# Caminho completo para o arquivo de log
# Script deve ser executado com privilégios de root (ex: sudo ./script.sh) para gravar aqui
LOG_FILE="/var/log/chromium_kiosk.log"

# ============================================
#             FIM DAS CONFIGURAÇÕES
# ============================================


# Garante que o diretório de log exista
mkdir -p "$(dirname "$LOG_FILE")"

# Redireciona stdout e stderr para o arquivo de log e também para o console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Script iniciado em $(date) ---"
echo "$(date): Log sendo salvo em: $LOG_FILE \n \n"

# --- Coleta a URL do prompt ---
echo -n "Por favor, digite a URL do site para o quiosque (ex: https://exemplo.com): "
read KIOSK_URL

# Validação básica da URL (opcional, mas recomendado)
if [[ -z "$KIOSK_URL" ]]; then
    echo "$(date): ERRO: Nenhuma URL foi fornecida. O script será encerrado."
    exit 1
fi

echo "$(date): URL do quiosque configurada para: $KIOSK_URL"

# --- Parte de configuração de ambiente X (CRÍTICA para interação com GUI) ---
DISPLAY_VAR=":0" # Display padrão para sessão gráfica
X_USER=$(who | awk '/:0|:1/ {print $1; exit}') # Tenta determinar o usuário da sessão X
if [ -z "$X_USER" ]; then
    echo "$(date): ALERTA: Não foi possível determinar o usuário do display X. Tentando 'pi' por padrão."
    X_USER="pi" # Fallback comum para Raspberry Pi
fi

# Tenta encontrar o arquivo XAUTHORITY do usuário da sessão X
XAUTHORITY_FILE="/home/$X_USER/.Xauthority"
if [ ! -f "$XAUTHORITY_FILE" ]; then
    echo "$(date): ERRO CRÍTICO: Arquivo XAUTHORITY não encontrado em $XAUTHORITY_FILE para o usuário $X_USER."
    echo "$(date): Sem este arquivo, comandos GUI (xset, unclutter, xdotool) podem falhar ou o Chromium não iniciar corretamente."
    echo "$(date): Verifique se o usuário $X_USER está logado graficamente e se o .Xauthority existe."
    # Se este erro ocorrer, o script provavelmente não funcionará conforme o esperado.
    # Considere abortar ou tentar iniciar o XAUTHORITY se for um problema de inicialização.
fi
# --- Fim da parte de configuração de ambiente X ---

# Desabilita o screensaver e gerenciamento de energia
# Executado como o usuário da sessão X para garantir que as configurações se apliquem corretamente
sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" xset s noblank
sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" xset s off
sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" xset -dpms
echo "$(date): Screensaver e DPMS desabilitados (para o usuário $X_USER)."

# Esconde o cursor do mouse quando ocioso
sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" unclutter -idle 0.5 -root &
echo "$(date): unclutter iniciado em segundo plano para o usuário $X_USER."

# Corrige possíveis problemas de encerramento do Chromium
# Executa como o usuário da sessão X para modificar o perfil correto do Chromium.
sudo -u "$X_USER" sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "/home/$X_USER/.config/chromium/Default/Preferences"
sudo -u "$X_USER" sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "/home/$X_USER/.config/chromium/Default/Preferences"
echo "$(date): Preferências do Chromium ajustadas para o usuário $X_USER."

# Abre o Chromium em modo quiosque
# Inicia o Chromium como o usuário da sessão X
sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" /usr/bin/chromium-browser --noerrdialogs --disable-infobars --kiosk "$KIOSK_URL" &
echo "$(date): Chromium iniciado em modo quiosque como usuário $X_USER, exibindo $KIOSK_URL."

# Armazena o PID do Chromium para possível uso futuro (opcional)
CHROMIUM_PID=$!
echo "$(date): PID do comando de início do Chromium: $CHROMIUM_PID"

# Loop principal para verificação e atualização
while true; do
    echo "$(date): Verificando status da URL $KIOSK_URL..."
    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" "$KIOSK_URL")
    echo "$(date): Status HTTP retornado: $HTTP_STATUS"

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "$(date): Site retornou 200 OK. Aguardando 1 minuto para a próxima verificação."
        sleep 60 # Espera 1 minuto para a próxima verificação
    else
        echo "$(date): Site retornou $HTTP_STATUS. Reiniciando Chromium para forçar o refresh."
        while [ "$HTTP_STATUS" -ne 200 ]; do
            echo "$(date): Encerrando processos do Chromium para o usuário $X_USER..."
            sudo -u "$X_USER" pkill chromium-browser
            sleep 5 # Dá um tempo para o processo morrer completamente

            echo "$(date): Reiniciando Chromium em modo quiosque como usuário $X_USER..."
            sudo -u "$X_USER" env DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTHORITY_FILE" /usr/bin/chromium-browser --noerrdialogs --disable-infobars --kiosk "$KIOSK_URL" &
            CHROMIUM_PID=$!
            echo "$(date): Chromium reiniciado. Novo PID do comando: $CHROMIUM_PID"

            sleep 60 # Espera 1 minuto antes da próxima re-verificação
            echo "$(date): Re-verificando status após 1 minuto do reinício..."
            HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" "$KIOSK_URL")
            echo "$(date): Status HTTP após reinício: $HTTP_STATUS"
        done
        echo "$(date): Site voltou a retornar 200 OK. Voltando à verificação a cada 1 minuto."
    fi
done