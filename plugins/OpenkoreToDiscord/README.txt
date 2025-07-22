
# OpenKore to Discord Notifier

Um plugin para OpenKore que envia notificações ricas e detalhadas sobre as atividades do seu bot diretamente para um canal do Discord via Webhook.

## 📜 Descrição

Este plugin monitora uma vasta gama de eventos dentro do OpenKore — de alertas de status a eventos de combate e farm — e os relata em tempo real no Discord. As notificações podem ser enviadas como mensagens de texto simples ou como "embeds" (painéis ricos e coloridos) para uma visualização mais organizada e agradável.

É a ferramenta perfeita para monitorar a atividade do seu personagem, garantir sua segurança e acompanhar seu progresso sem precisar olhar constantemente para o console do OpenKore.

-----

## ✨ Funcionalidades Principais

O plugin é capaz de notificar sobre os seguintes eventos:

  * **Eventos do Personagem:**
      * **Level Up:** Avisa quando o nível de Base ou de Classe aumenta.
      * **Morte:** Envia um alerta imediato quando o personagem morre, incluindo o mapa e as coordenadas.
      * **Status Baixo:** Alertas personalizáveis para HP e SP baixos.
      * **Excesso de Peso:** Notificação quando o peso carregado ultrapassa um limite definido.
  * **Farm e Itens:**
      * **Loot Raro:** Receba um aviso ao dropar itens valiosos (ex: Cartas, Equipamentos Visuais, etc.).
      * **MVP Derrotado:** Comemore a derrota de um MVP com uma notificação especial.
      * **Venda Automática:** Relatório com o total de zeny ganho após vender itens no NPC.
      * **Armazenamento Automático:** Lista de itens guardados no armazém.
  * **Interação e Segurança:**
      * **Mensagens Privadas (PM):** Exibe o conteúdo de PMs recebidas.
      * **GM Detectado:** Envia um alerta de alta prioridade se um Game Master aparecer na tela.
      * **Atividade da Loja:** Notifica quando sua loja de venda é aberta, fechada ou quando um item é vendido.
  * **Relatórios e Status:**
      * **Resumo Periódico:** Envia um relatório completo em intervalos de tempo definidos, com uptime, zeny/hora, exp/hora e os monstros mais caçados.
      * **Status sob Demanda:** Use o comando `dstatus` no console para receber um status detalhado instantaneamente.
      * **Conexão:** Informa quando o bot é conectado, desconectado ou quando o plugin é iniciado/parado.

-----

## ⚙️ Instalação

A instalação é simples e segue o padrão dos plugins do OpenKore.

1.  **Baixe o Plugin:**

      * Faça o download do arquivo `OpenkoreToDiscord.pl`.

2.  **Mova o Arquivo:**

      * Coloque o arquivo `OpenkoreToDiscord.pl` dentro da pasta `plugins` do seu OpenKore.

3.  **Inicie o OpenKore:**

      * Inicie o OpenKore uma vez. O plugin criará automaticamente um arquivo de configuração chamado `Openkoretodiscord.conf` dentro da pasta `plugins`.

4.  **Configure o Webhook:**

      * Abra o arquivo `Openkoretodiscord.conf` com um editor de texto.
      * A primeira e mais importante configuração é a `webhook_url`. Você precisa criar um Webhook em um canal do seu servidor do Discord e colar a URL aqui.
      * Para criar um Webhook: Vá em `Editar Canal` \> `Integrações` \> `Webhooks` \> `Novo Webhook`. Copie a URL do Webhook.

5.  **Personalize (Opcional):**

      * Ajuste as outras opções no arquivo de configuração para ativar/desativar as notificações que desejar. Salve o arquivo.

6.  **Reinicie o OpenKore:**

      * Reinicie o OpenKore ou recarregue o plugin com o comando `plugin reload discord`.

Pronto\! As notificações começarão a chegar no seu canal do Discord.

-----

## 🔧 Configuração

Todas as configurações são feitas no arquivo `Openkoretodiscord.conf`. Você pode ativar, desativar e personalizar cada notificação.

| Chave | Padrão | Descrição |
| :--- | :--- | :--- |
| **`webhook_url`** | *vazio* | **(OBRIGATÓRIO)** A URL do seu Webhook do Discord. |
| `notification_mode` | `embed` | Modo de notificação. Use `embed` para painéis ricos ou `text` para mensagens simples. |
| `char_name_override` | *vazio* | Use um nome personalizado para o bot no Discord. Se vazio, usa o nome do personagem. |
| `notify_on_level_up` | `1` | Notificar ao subir de nível de base ou classe. `1`=ativado, `0`=desativado. |
| `notify_on_death` | `1` | Notificar ao morrer. |
| `notify_on_map_change`| `1` | Notificar ao mudar de mapa. |
| `notify_on_pm` | `1` | Notificar ao receber uma mensagem privada. |
| `notify_on_low_hp` | `1` | Ativar alerta de HP baixo. |
| `hp_threshold` | `30` | Porcentagem (%) de HP para ativar o alerta. |
| `notify_on_low_sp` | `1` | Ativar alerta de SP baixo. |
| `sp_threshold` | `20` | Porcentagem (%) de SP para ativar o alerta. |
| `notify_on_high_weight`| `1` | Ativar alerta de peso alto. |
| `weight_threshold` | `85` | Porcentagem (%) de peso para ativar o alerta. |
| `notify_on_rare_loot` | `1` | Ativar alerta de loot raro. |
| `rare_loot_keywords` | `Carta,Caixa...`| Palavras-chave (separadas por vírgula) para identificar um loot raro. |
| `notify_on_mvp_kill` | `1` | Ativar alerta ao derrotar um MVP. |
| `mvp_names` | `Baphomet,...` | Nomes dos MVPs (separados por vírgula) a serem monitorados. |
| `notify_on_autosell` | `1` | Notificar após a venda automática para NPCs. |
| `notify_on_autostorage`| `1` | Notificar após guardar itens no armazém. |
| `notify_on_gm_sighting`| `1` | Notificar ao avistar um GM. |
| `notify_on_shop_activity` | `1` | Notificar sobre atividades da loja de venda (abrir, fechar, vender). |
| `summary_interval` | `900` | Intervalo em segundos para enviar o relatório periódico (padrão: 15 minutos). |
| `max_zeny_rate_sanity_check` | `50000000` | Um limite para a taxa de zeny/h para evitar relatórios com valores absurdos. |

-----

## 🚀 Uso

Além das notificações automáticas, você pode interagir com o plugin através de um comando no console do OpenKore:

  * **`dstatus`**
      * Digite `dstatus` no console do seu OpenKore.
      * O plugin enviará imediatamente um relatório de status completo para o seu canal do Discord, contendo informações como Nível, HP/SP, Mapa, Peso e Zeny.

-----

## ✍️ Autores

  * **Desenvolvimento:** Doc (megancheetus) e Sonic
  * **Versão:** 5.1 (Definitiva) - 11 de Julho de 2025
