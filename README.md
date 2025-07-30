# O que este script faz e como ele funciona?

Este script foi feito para transformar seu Raspberry Pi em um quiosque digital. Ele exibe um site específico em tela cheia, funciona sozinho e consegue se recuperar de problemas de conexão.

- Prepara o sistema: Instala ferramentas essenciais (como as que escondem o mouse e simulam teclas) e configura o Chromium pra iniciar sempre em modo quiosque (tela cheia), sem barras ou avisos. Ele também desativa o protetor de tela do sistema.

- Pede o site: No início, ele te pergunta qual endereço da web (URL) você quer que o quiosque mostre.

- Monitora e gerencia:

    - Cria um serviço inteligente que faz o navegador e o monitoramento começarem automaticamente toda vez que o Raspberry Pi liga.

    - Fica verificando a URL a cada minuto. Se o site sair do ar, ele reinicia o navegador a cada 1 minuto até o site voltar.

    - Assim que o site volta a funcionar, ele reinicia o navegador de novo pra ter certeza que a página está totalmente atualizada.

    - Reinicia pra ativar: Por último, ele reinicia o Raspberry Pi pra que todas as configurações e o modo quiosque comecem a funcionar corretamente.

# Como ele funciona:

Você executa [este script](https://raw.githubusercontent.com/tiagojulianoferreira/raspberry-kiosk/refs/heads/main/install_kiosk.sh) apenas uma vez pra configurar seu quiosque. Depois disso, ele cuida de tudo sozinho. Garante que seu Raspberry Pi esteja sempre mostrando o site que você escolheu, mesmo que a internet caia ou o servidor do site tenha problemas. 

# Execução em comando único
```shell
bash -c "$(wget -qO- https://raw.githubusercontent.com/tiagojulianoferreira/raspberry-kiosk/refs/heads/main/install_kiosk.sh)"
```

