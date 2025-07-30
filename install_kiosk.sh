#!/bin/bash

echo "Instala dependências necessárias..."
sudo apt-get update
sudo apt-get install -y chromium-browser unclutter xdotool curl

echo "Configura Navegador Chromium para TV"

# --- Conteúdo do script kiosk.sh ---
# Este conteúdo será escrito para /home/pi/kiosk.sh
read -r -d '' kiosk_script_content << EOF
#!/bin/bash

# ============================================
#               CONFIGURAÇÕES
# ============================================

# Caminho completo para o arquivo de log
# Script deve ser executado com privilégios de root (ex: sudo ./script.sh) para gravar aqui
LOG_FILE="/var/log/chromium_kiosk.log"

# Número máximo de linhas a serem mantidas no arquivo de log
# Se o arquivo exceder este número, as linhas mais antigas serão removidas.
# ATENÇÃO: Se você usa logrotate, desative ou ajuste esta função para evitar conflitos.
MAX_LOG_LINES=500 # Exemplo: manter as últimas 500 linhas

# ============================================
#             FIM DAS CONFIGURAÇÕES
# ============================================


# Garante que o diretório de log exista
mkdir -p "$(dirname "$LOG_FILE")"

# Função para aparar o arquivo de log
trim_log_file() {
    if [ -f "$LOG_FILE" ]; then
        local current_lines=$(wc -l < "$LOG_FILE")
        if [ "$current_lines" -gt "$MAX_LOG_LINES" ]; then
            tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
            echo "$(date): Log aparado para as últimas $MAX_LOG_LINES linhas."
        fi
    fi
}


# Redireciona stdout e stderr para o arquivo de log e também para o console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Script iniciado em $(date) ---"
echo "$(date): Log sendo salvo em: $LOG_FILE"

# --- Coleta a URL do prompt ---
echo -n "Por favor, digite a URL do site para o quiosque (ex: https://exemplo.com): "
# read KIOSK_URL
# Para scripts que rodam como serviço, a interação via "read" não é ideal.
# Em um serviço, a URL deve ser passada como argumento, ou configurada via ambiente.
# Por enquanto, vamos manter a URL fixa aqui ou removê-la para o prompt do instalador.
# Se este kiosk.sh for executado diretamente pelo serviço, ele não terá prompt.
# A URL deve vir de fora ou ser fixa. Para este cenário de serviço,
# vou remover o 'read' e a URL será definida no serviço ou será uma constante no kiosk.sh.
# Vamos voltar para KIOSK_URL no topo do kiosk.sh, pois o serviço não pode interagir com o usuário.

# Se você quer a URL DINÂMICA com o serviço, ela precisaria ser passada como um argumento
# para o kiosk.sh via a linha ExecStart do serviço, ou o kiosk.sh teria que ler um arquivo de config.
# Por simplicidade e confiabilidade em um serviço, manterei a URL como uma variável interna do kiosk.sh.
# O instalador (este script) irá *escrever* essa URL no kiosk.sh antes de salvá-lo.

# placeholder para KIOSK_URL no kiosk.sh - será substituído pelo script instalador
KIOSK_URL_PLACEHOLDER="___KIOSK_URL_PLACEHOLDER___"
KIOSK_URL="$KIOSK_URL_PLACEHOLDER" # Será substituído pelo instalador

echo "$(date): URL do quiosque configurada para: $KIOSK_URL"


# --- Parte de configuração de ambiente X (CRÍTICA para interação com GUI) ---
DISPLAY_VAR=":0" # Display padrão para sessão gráfica
X_USER=\$(who | awk '/:0|:1/ {print \$1; exit}') # Tenta determinar o usuário da sessão X
if [ -z "\$X_USER" ]; then
    echo "$(date): ALERTA: Não foi possível determinar o usuário do display X. Tentando 'pi' por padrão."
    X_USER="pi" # Fallback comum para Raspberry Pi
fi

# Tenta encontrar o arquivo XAUTHORITY do usuário da sessão X
XAUTHORITY_FILE="/home/\$X_USER/.Xauthority"
if [ ! -f "\$XAUTHORITY_FILE" ]; then
    echo "$(date): ERRO CRÍTICO: Arquivo XAUTHORITY não encontrado em \$XAUTHORITY_FILE para o usuário \$X_USER."
    echo "$(date): Sem este arquivo, comandos GUI (xset, unclutter) podem falhar ou o Chromium não iniciar corretamente."
    echo "$(date): Verifique se o usuário \$X_USER está logado graficamente e se o .Xauthority existe."
fi
# --- Fim da parte de configuração de ambiente X ---

# Desabilita o screensaver e gerenciamento de energia
sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" xset s noblank
sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" xset s off
sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" xset -dpms
echo "$(date): Screensaver e DPMS desabilitados (para o usuário \$X_USER)."

# Esconde o cursor do mouse quando ocioso
sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" unclutter -idle 0.5 -root &
echo "$(date): unclutter iniciado em segundo plano para o usuário \$X_USER."

# Corrige possíveis problemas de encerramento do Chromium
sudo -u "\$X_USER" sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "/home/\$X_USER/.config/chromium/Default/Preferences"
sudo -u "\$X_USER" sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "/home/\$X_USER/.config/chromium/Default/Preferences"
echo "$(date): Preferências do Chromium ajustadas para o usuário \$X_USER."

# Abre o Chromium em modo quiosque
sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" /usr/bin/chromium-browser --noerrdialogs --disable-infobars --kiosk "\$KIOSK_URL" &
echo "$(date): Chromium iniciado em modo quiosque como usuário \$X_USER, exibindo \$KIOSK_URL."

CHROMIUM_PID=\$!
echo "$(date): PID do comando de início do Chromium: \$CHROMIUM_PID"

# Loop principal para verificação e atualização
while true; do
    echo "$(date): Verificando status da URL \$KIOSK_URL..."
    HTTP_STATUS=\$(curl -o /dev/null -s -w "%{http_code}\\n" "\$KIOSK_URL")
    echo "$(date): Status HTTP retornado: \$HTTP_STATUS"

    if [ "\$HTTP_STATUS" -eq 200 ]; then
        echo "$(date): Site retornou 200 OK. Aguardando 1 minuto para a próxima verificação."
        sleep 60
    else
        echo "$(date): Site retornou \$HTTP_STATUS. Reiniciando Chromium para forçar o refresh."
        while [ "\$HTTP_STATUS" -ne 200 ]; do
            echo "$(date): Encerrando processos do Chromium para o usuário \$X_USER..."
            sudo -u "\$X_USER" pkill chromium-browser
            sleep 5

            echo "$(date): Reiniciando Chromium em modo quiosque como usuário \$X_USER..."
            sudo -u "\$X_USER" env DISPLAY="\$DISPLAY_VAR" XAUTHORITY="\$XAUTHORITY_FILE" /usr/bin/chromium-browser --noerrdialogs --disable-infobars --kiosk "\$KIOSK_URL" &
            CHROMIUM_PID=\$!
            echo "$(date): Chromium reiniciado. Novo PID do comando: \$CHROMIUM_PID"

            sleep 300
            echo "$(date): Re-verificando status após 5 minutos do reinício..."
            HTTP_STATUS=\$(curl -o /dev/null -s -w "%{http_code}\\n" "\$KIOSK_URL")
            echo "$(date): Status HTTP após reinício: \$HTTP_STATUS"
            trim_log_file # Chama a função para aparar o log
        done
        echo "$(date): Site voltou a retornar 200 OK. Voltando à verificação a cada 1 minuto."
    fi
    trim_log_file # Chama a função para aparar o log
done
EOF

# Coleta a URL do prompt ANTES de escrever o kiosk.sh
echo -n "Por favor, digite a URL do site para o quiosque (ex: https://exemplo.com): "
read KIOSK_URL_FROM_PROMPT

# Validação básica da URL (opcional, mas recomendado)
if [[ -z "$KIOSK_URL_FROM_PROMPT" ]]; then
    echo "ERRO: Nenhuma URL foi fornecida. O script será encerrado."
    exit 1
fi

# Substitui o placeholder da URL no conteúdo do script antes de salvá-lo
kiosk_script_content="${kiosk_script_content//___KIOSK_URL_PLACEHOLDER___/$KIOSK_URL_FROM_PROMPT}"

echo "Criando /home/pi/kiosk.sh..."
echo "$kiosk_script_content" | sudo tee /home/pi/kiosk.sh > /dev/null
sudo chmod +x /home/pi/kiosk.sh
echo "/home/pi/kiosk.sh criado e com permissões de execução."

sleep 2

echo "Habilita TUB-KIOSK como Serviço..."
kiosk_service_content='
[Unit]
Description=Chromium Kiosk
Wants=graphical.target
After=graphical.target

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
Type=simple
ExecStart=/bin/bash /home/pi/kiosk.sh
Restart=on-failure
User=pi
Group=pi

[Install]
WantedBy=graphical.target
'
echo "$kiosk_service_content" | sudo tee /lib/systemd/system/kiosk.service > /dev/null
echo "kiosk.service criado."

sudo systemctl enable kiosk.service
echo "kiosk.service habilitado."
sleep 2
sudo systemctl start kiosk.service
echo "kiosk.service iniciado."
sleep 3
sudo reboot
echo "Sistema será reiniciado para aplicar as mudanças."