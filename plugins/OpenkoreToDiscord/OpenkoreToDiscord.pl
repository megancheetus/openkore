package OpenkoreToDiscord;

# ====================================================================
# Plugin OpenkoreToDiscord
#
# Autor: Doc (megancheetus) e Sonic com revisão;
# Autor: Sherolayne, com pequenas modificações do Doc  e Sonic.
# Data da Versão: 11 de Julho de 2025
#
# Descrição:
# Este plugin envia notificações ricas e detalhadas das atividades  do OpenKore para um canal do Discord via Webhook. 
# ====================================================================

use strict;
use warnings;
use utf8;

# Módulos Perl
use LWP::UserAgent;
use JSON qw(encode_json);
use Encode qw(decode encode is_utf8);
use Scalar::Util qw(reftype);

# Módulos OpenKore
use Plugins;
use Globals;
use Log qw(message error warning);
use Utils;

# --- Registro e Informações do Plugin ---
my $plugin_folder = $Plugins::current_plugin_folder;
my $plugin_version = "5.1 (Definitiva)";
Plugins::register("discord", "Discord Webhook Notifier v$plugin_version", \&on_unload);

# --- Configuração ---
my %CONFIG;
my $config_file = "$plugin_folder/Openkoretodiscord.conf";
sub load_config {
    %CONFIG = (
        webhook_url => '', notification_mode => 'embed', char_name_override => '',
        notify_on_level_up => 1, notify_on_death => 1, notify_on_map_change => 1, notify_on_pm => 1,
        notify_on_low_hp => 1, hp_threshold => 30, notify_on_low_sp => 1, sp_threshold => 20,
        notify_on_high_weight => 1, weight_threshold => 85,
        notify_on_rare_loot => 1, rare_loot_keywords => 'Carta,Caixa,Galho,Álbum,Presente,Raro,Épico,Visual',
        notify_on_mvp_kill => 1, mvp_names => 'Baphomet,Doppelganger,Eddga,Pharaoh,Mistress,Orc Hero,Orc Lord,Osiris,Amon Ra,Dracula,Garm,Maya',
        notify_on_autosell => 1, notify_on_autostorage => 1,
        notify_on_gm_sighting => 1, notify_on_shop_activity => 1,
        summary_interval => 900, max_zeny_rate_sanity_check => 50_000_000,
    );
    if (-f $config_file) {
        open my $fh, '<:encoding(UTF-8)', $config_file or return;
        while (my $line = <$fh>) { chomp $line; $line =~ s/#.*//; if ($line =~ /^\s*(\w+)\s*=\s*(.*?)\s*$/) { $CONFIG{$1} = $2; } }
        close $fh;
    } else {
        open my $fh, '>:encoding(UTF-8)', $config_file or die "Não foi possível criar $config_file: $!";
        print $fh "# --- Configuração Essencial ---\n";
        print $fh "webhook_url = \n";
        print $fh "notification_mode = embed\n";
        print $fh "char_name_override = \n\n";
        print $fh "# --- Notificações de Eventos (1 = Ativado, 0 = Desativado) ---\n";
        print $fh "notify_on_level_up = 1\n";
        print $fh "notify_on_death = 1\n";
        print $fh "notify_on_map_change = 1\n";
        print $fh "notify_on_pm = 1\n\n";
        print $fh "# --- Alertas de Status do Personagem ---\n";
        print $fh "notify_on_low_hp = 1\n";
        print $fh "hp_threshold = 30\n";
        print $fh "notify_on_low_sp = 1\n";
        print $fh "sp_threshold = 20\n";
        print $fh "notify_on_high_weight = 1\n";
        print $fh "weight_threshold = 85\n\n";
        print $fh "# --- Alertas de Farm e Itens ---\n";
        print $fh "notify_on_rare_loot = 1\n";
        print $fh "rare_loot_keywords = $CONFIG{rare_loot_keywords}\n";
        print $fh "notify_on_mvp_kill = 1\n";
        print $fh "mvp_names = $CONFIG{mvp_names}\n";
        print $fh "notify_on_autosell = 1\n";
        print $fh "notify_on_autostorage = 1\n\n";
        print $fh "# --- Alertas de Segurança e Loja ---\n";
        print $fh "notify_on_gm_sighting = 1\n";
        print $fh "notify_on_shop_activity = 1\n\n";
        print $fh "# --- Relatórios ---\n";
        print $fh "summary_interval = 900\n";
        print $fh "max_zeny_rate_sanity_check = 50000000\n";
        close $fh;
        error "[Discord] Arquivo de configuração criado. Por favor, edite '$config_file' com a URL do seu webhook.\n";
    }
    $CONFIG{_rare_loot_hash} = { map { lc($_) => 1 } split ',', lc($CONFIG{rare_loot_keywords}) };
    $CONFIG{_mvp_hash} = { map { $_ => 1 } split ',', $CONFIG{mvp_names} };
}
load_config();

# --- Estado Interno do Plugin ---
my %STATE = (
    kills => {}, total_kills => 0, start_time => time,
    last_summary_time => time, last_summary_zeny => $char->{zeny} // 0, last_summary_exp => $char->{exp} // 0,
    last_base_level => $char->{lv} || 0, last_job_level => $char->{lv_job} || 0,
    hp_warned => 0, sp_warned => 0, weight_warned => 0,
    is_selling => 0, zeny_from_this_sale => 0,
    last_notified_map => '',
);

# --- Módulo de Comunicação com Discord ---
my $UA = LWP::UserAgent->new(agent => "OpenKore-Discord/$plugin_version", timeout => 15);
sub notify { my ($data) = @_; return unless $data; if (lc($CONFIG{notification_mode}) eq 'embed') { send_embed($data); } else { send_message($data->{simple_text}); }}
sub send_message { my ($message_text) = @_; return unless ($CONFIG{webhook_url} && $CONFIG{webhook_url} =~ m!^https://discord\.com/api/webhooks/!); my $char_name = $CONFIG{char_name_override} || ($char ? $char->{name} : 'Bot'); $message_text = "[$char_name] $message_text"; my $response = $UA->post($CONFIG{webhook_url}, 'Content-Type' => 'application/json', 'Content' => encode_json({ content => $message_text })); unless ($response->is_success) { error "[Discord] Falha ao enviar notificação: " . $response->status_line . "\n"; }}
sub send_embed { my ($embed_data) = @_; return unless ($CONFIG{webhook_url} && $CONFIG{webhook_url} =~ m!^https://discord\.com/api/webhooks/!); my $char_name = $CONFIG{char_name_override} || ($char ? $char->{name} : 'Bot'); my $payload = { username => $char_name, avatar_url => 'https://i.imgur.com/v1hMxU1.png', embeds => [{ title => $embed_data->{title}, description => $embed_data->{description}, color => $embed_data->{color} || 0x3498DB, fields => $embed_data->{fields}, timestamp => time_iso(), }], }; my $response = $UA->post($CONFIG{webhook_url}, 'Content-Type' => 'application/json', 'Content' => encode_json($payload)); unless ($response->is_success) { error "[Discord] Falha ao enviar notificação rica: " . $response->status_line . "\n"; }}

# --- Handlers de Eventos ---
sub on_self_died { return unless $CONFIG{notify_on_death}; my $pos = ($char && $char->{pos_to}{x} && $char->{pos_to}{y}) ? "($char->{pos_to}{x}, $char->{pos_to}{y})" : "coordenadas desconhecidas"; notify({ title => "💀 Você Morreu!", description => "Morto no mapa **" . _map() . "** em **$pos**.", color => 0xE74C3C, simple_text => "💀 MORREU no mapa " . _map() . " em $pos", }); }
sub on_map_change_event { return unless $CONFIG{notify_on_map_change}; my (undef, $args) = @_; my $current_map = ($args && $args->{map}) ? $args->{map} : _map(); $current_map =~ s/\.gat$// if $current_map; return unless defined $current_map; return if ($STATE{last_notified_map} && $STATE{last_notified_map} eq $current_map); notify({ title => "🌍 Mudança de Mapa", description => "Entrou em **" . $current_map . "**.", color => 0x1ABC9C, simple_text => "🌍 Entrou no mapa: " . $current_map, }); $STATE{last_notified_map} = $current_map; }
sub on_target_died { my (undef, $args) = @_; my $monster = $args->{monster}; return unless $monster; my $name = _utf8($monster->{name}); $STATE{kills}{$name}++; $STATE{total_kills}++; if ($CONFIG{notify_on_mvp_kill} && $CONFIG{_mvp_hash}{$name}) { notify({ title => "👑 MVP Derrotado!", description => "O MVP **$name** foi derrotado no mapa **" . _map() . "**.", color => 0xFFD700, simple_text => "👑 MVP Derrotado: $name no mapa " . _map() . "!", }); }}
sub on_item_gathered { return unless $CONFIG{notify_on_rare_loot}; my (undef, $args) = @_; my $item_data = $args->{item}; return unless $item_data; my $item_name = (reftype($item_data) eq 'HASH') ? $item_data->{name} : $item_data; return unless $item_name; $item_name = _utf8($item_name); foreach my $keyword (keys %{$CONFIG{_rare_loot_hash}}) { if (lc($item_name) =~ /$keyword/) { notify({ title => "🎁 Loot Raro Obtido!", description => "Pegou **$item_name**.", color => 0x2ECC71, simple_text => "🎁 Loot Raro Obtido: $item_name", }); last; }}}
sub on_level_change { return unless $CONFIG{notify_on_level_up}; my ($type) = @_; my ($new_level, $old_level_ref) = ($type eq 'Base') ? ($char->{lv}, \$STATE{last_base_level}) : ($char->{lv_job}, \$STATE{last_job_level}); return if $new_level <= $$old_level_ref; notify({ title => "🆙 Level Up de $type!", description => "Parabéns, nível de $type alcançou **$new_level**!", color => 0x9B59B6, simple_text => "🆙 Level Up de $type! Nível atual: $new_level", }); $$old_level_ref = $new_level; }
sub on_pm_received { return unless $CONFIG{notify_on_pm}; my (undef, $args) = @_; my $sender = _utf8($args->{privMsgUser} // 'Desconhecido'); my $message = _utf8($args->{privMsg}); notify({ title => "✉️ PM Recebido de $sender", description => "```$message```", color => 0x7F8C8D, simple_text => "✉️ PM de $sender: `$message`", }); }
sub on_gm_sighting { return unless $CONFIG{notify_on_gm_sighting}; my (undef, $args) = @_; notify({ title => "🚨 ALERTA DE GM 🚨", description => "Um **GM ($args->{name})** foi detectado próximo em **" . _map() . "**!", color => 0xFF0000, simple_text => "🚨 ALERTA: GM ($args->{name}) avistado em " . _map() . "!", }); }
sub on_shop_activity { return unless $CONFIG{notify_on_shop_activity}; my (undef, $args) = @_; my %messages = ( open_store_success => {t => "🏪 Loja Aberta", d => "Sua loja de venda foi aberta com sucesso.", c => 0x2ECC71, s => "🏪 Loja Aberta."}, shop_closed => {t => "Shop Fechado", d => "Sua loja de venda foi fechada.", c => 0xE74C3C, s => "Shop Fechado."}, vending_item_sold => {t => "Item Vendido!", d => "Vendeu **$args->{item_name}** por **" . commify($args->{price}) . " zeny**.", c => 0xF1C40F, s => "Vendeu $args->{item_name} por " . commify($args->{price}) . " z."},); my $msg = $messages{$args->{type}}; notify({title => $msg->{t}, description => $msg->{d}, color => $msg->{c}, simple_text => $msg->{s}}); }
sub on_autosell_start { $STATE{is_selling} = 1; $STATE{zeny_from_this_sale} = 0; }
sub on_system_message { return unless $STATE{is_selling}; my (undef, $args) = @_; my $msg = $args->{msg_str}; if ($msg =~ /^Você ganhou ([\d,.]+) zeny\.$/) { my $gained = $1; $gained =~ s/[.,]//g; $STATE{zeny_from_this_sale} += $gained; } }
sub on_autosell_done { $STATE{is_selling} = 0; return unless $CONFIG{notify_on_autosell}; my $gained = $STATE{zeny_from_this_sale}; if ($gained > 0) { notify({ title => "💰 Venda Automática Realizada", description => "A venda de itens para o NPC foi concluída com precisão.", fields => [{ name => "Zeny Obtido", value => "**" . commify($gained) . " z**", inline => 0 }], color => 0x00D166, simple_text => "💰 Venda automática concluída. Zeny obtido: " . commify($gained) . " z.", }); }}
sub on_autostorage_done { return unless $CONFIG{notify_on_autostorage}; my (undef, $args) = @_; my $stored_items = $args->{stored}; return unless ($stored_items && %$stored_items); my @items_list; foreach my $item_name (sort keys %$stored_items) { my $amount = $stored_items->{$item_name}; push @items_list, "• $item_name x $amount"; } my $description = "Os seguintes itens foram guardados no armazém:\n" . join("\n", @items_list); if (length($description) > 2000) { $description = substr($description, 0, 1997) . "..."; } notify({ title => "📦 Itens Guardados no Armazém", description => $description, color => 0x546E7A, simple_text => "📦 Itens guardados no armazém. (" . scalar(@items_list) . " tipos de item)", }); }
sub periodic_summary { my $now = time; my $current_zeny = $char->{zeny} // 0; my $current_exp = $char->{exp} // 0; my $interval_seconds = $now - $STATE{last_summary_time}; return if $interval_seconds < 60; my $interval_hours = $interval_seconds / 3600; my $zeny_delta = $current_zeny - $STATE{last_summary_zeny}; my $zeny_rate_raw = $zeny_delta / $interval_hours; my $zeny_rate_str; if ($zeny_rate_raw > $CONFIG{max_zeny_rate_sanity_check}) { $zeny_rate_str = "Anomalia detectada!"; } else { $zeny_rate_str = commify(int($zeny_rate_raw)) . " z/h"; } my $exp_delta = $current_exp - $STATE{last_summary_exp}; my $exp_rate_str = commify(int($exp_delta / $interval_hours)) . " exp/h"; my @top_kills = sort { $STATE{kills}{$b} <=> $STATE{kills}{$a} } keys %{$STATE{kills}}; my $top_kills_str = "Nenhum monstro morto."; if (@top_kills) { my @lines; for my $i (0 .. ($#top_kills > 2 ? 2 : $#top_kills)) { push @lines, "• $top_kills[$i]: **" . ($STATE{kills}{$top_kills[$i]} || 0) . "**"; } $top_kills_str = join("\n", @lines); } notify({ title => "📊 Resumo da Sessão", fields => [ { name => "Uptime", value => format_uptime($now - $STATE{start_time}), inline => 1 }, { name => "Zeny Atual", value => commify($current_zeny), inline => 1 }, { name => "Kills Totais", value => $STATE{total_kills}, inline => 1 }, { name => "Taxa de Zeny (recente)", value => $zeny_rate_str, inline => 1 }, { name => "Taxa de EXP (recente)", value => $exp_rate_str, inline => 1 }, { name => "EXP Base Atual", value => ($char->{exp_max} ? sprintf("%.2f%%", $char->{exp} * 100 / $char->{exp_max}) : "N/A"), inline => 1 }, { name => "EXP Classe Atual", value => ($char->{exp_job_max} ? sprintf("%.2f%%", $char->{exp_job} * 100 / $char->{exp_job_max}) : "N/A"), inline => 1 }, { name => "Top 3 Kills", value => $top_kills_str, inline => 0 }, ], simple_text => "📊 Resumo: Zeny/h $zeny_rate_str, EXP/h $exp_rate_str, Kills $STATE{total_kills}.", }); $STATE{last_summary_time} = $now; $STATE{last_summary_zeny} = $current_zeny; $STATE{last_summary_exp} = $current_exp; }
sub do_status_command {
    
    return unless ($main::state == $main::S_IN_GAME && $char);
    
    my $hp_perc = int($char->{hp} * 100 / $char->{hp_max}); my $sp_perc = int($char->{sp} * 100 / $char->{sp_max}); my $wt_perc = int($char->{weight} * 100 / $char->{weight_max}); my $exp_perc = sprintf("%.2f%%", $char->{exp} * 100 / $char->{exp_max}); my $jexp_perc = sprintf("%.2f%%", $char->{exp_job} * 100 / $char->{exp_max_job}); notify({ title => "📋 Status de $char->{name}", fields => [ { name => "Nível", value => "$char->{lv} / $char->{lv_job}", inline => 1 }, { name => "HP", value => "$hp_perc% ($char->{hp}/$char->{hp_max})", inline => 1 }, { name => "SP", value => "$sp_perc% ($char->{sp}/$char->{sp_max})", inline => 1 }, { name => "Mapa", value => _map() . " ($char->{pos}{x}, $char->{pos}{y})", inline => 1 }, { name => "Peso", value => "$wt_perc% ($char->{weight}/$char->{weight_max})", inline => 1 }, { name => "Zeny", value => commify($char->{zeny}), inline => 1 }, { name => "Exp Base", value => "$exp_perc", inline => 1 }, { name => "Exp Classe", value => "$jexp_perc", inline => 1 }, ], simple_text => "📋 Status: Lvl $char->{lv}/$char->{lv_job}, HP $hp_perc%, SP $sp_perc%, Mapa " . _map(), });
}

# --- Loop Principal (tick) ---
sub tick { my $now = time; if ($now - $STATE{last_summary_time} >= 0 + $CONFIG{summary_interval}) { periodic_summary(); } my $hp_p = int($char->{hp} * 100 / $char->{hp_max}); if ($CONFIG{notify_on_low_hp} && $hp_p < $CONFIG{hp_threshold}) { if (!$STATE{hp_warned}) { notify({title => "❤️ HP Baixo!", description => "Seu HP está em **$hp_p%**.", color => 0xFFA500, simple_text => "❤️ HP Baixo: $hp_p%!"}); $STATE{hp_warned} = 1; }} elsif ($STATE{hp_warned} && $hp_p > $CONFIG{hp_threshold} + 10) { $STATE{hp_warned} = 0; } my $sp_p = int($char->{sp} * 100 / $char->{sp_max}); if ($CONFIG{notify_on_low_sp} && $sp_p < $CONFIG{sp_threshold}) { if (!$STATE{sp_warned}) { notify({title => "💧 SP Baixo!", description => "Seu SP está em **$sp_p%**.", color => 0x3498DB, simple_text => "💧 SP Baixo: $sp_p%!"}); $STATE{sp_warned} = 1; }} elsif ($STATE{sp_warned} && $sp_p > $CONFIG{sp_threshold} + 10) { $STATE{sp_warned} = 0; } my $wt_p = int($char->{weight} * 100 / $char->{weight_max}); if ($CONFIG{notify_on_high_weight} && $wt_p > $CONFIG{weight_threshold}) { if (!$STATE{weight_warned}) { notify({title => "🎒 Peso Alto!", description => "Seu peso está em **$wt_p%**.", color => 0x95A5A6, simple_text => "🎒 Peso Alto: $wt_p%!"}); $STATE{weight_warned} = 1; }} elsif ($STATE{weight_warned} && $wt_p < $CONFIG{weight_threshold} - 5) { $STATE{weight_warned} = 0; }}

# --- Registro de Hooks e Comandos ---
my $hooks = Plugins::addHooks(
    ['target_died', \&on_target_died], ['item_gathered', \&on_item_gathered],
    ['base_level_changed', sub { on_level_change('Base') }], ['job_level_changed', sub { on_level_change('Job') }],
    ['self_died', \&on_self_died], ['packet_privMsg', \&on_pm_received],
    ['disconnected', sub { notify({title => "🔌 Bot Desconectado", color => 0x992D22, simple_text => "🔌 Bot Desconectado."}) }],
    ['avoidGM_near', \&on_gm_sighting],
    ['open_store_success', sub { on_shop_activity(undef, {type => 'open_store_success'}) }],
    ['shop_closed', sub { on_shop_activity(undef, {type => 'shop_closed'}) }],
    ['vending_item_sold', sub { return unless (reftype($_[1]) eq 'HASH'); on_shop_activity(undef, {type => 'vending_item_sold', item_name => $_[1]->{name}, price => $_[1]->{price}})}],
    ['AI_storage_done', \&on_autostorage_done],
    ['AI_pre', \&tick],
    ['packet_sysMsg', \&on_system_message],
    ['AI_sell_auto_start', \&on_autosell_start], ['AI_sell_auto_done', \&on_autosell_done],
    ['map_loaded', \&on_map_change_event], ['Network::Receive::map_changed', \&on_map_change_event],
);
eval { require Commands; import Commands; Commands::add(['dstatus'], "Envia um status detalhado para o Discord", \&do_status_command); message "[Discord] Comando 'dstatus' registrado com sucesso.\n"; };
if ($@) { warning "[Discord] Não foi possível registrar o comando 'dstatus'. O plugin continuará funcionando sem ele.\n"; }
sub on_unload { notify({title => "🛑 Plugin Desligado", simple_text => "🛑 Plugin Discord desligado."}); Plugins::delHooks($hooks); }

# --- Funções Auxiliares ---
sub commify { my $text = reverse shift; $text =~ s/(\d{3})(?=\d)(?!\d*\.)/$1,/g; return scalar reverse $text; }
sub _utf8 { my $s = shift // ''; return $s if is_utf8($s); return eval { decode('UTF-8', encode('iso-8859-1', $s), 1) } || $s; }
sub _map { return $field->baseName if ($field && $field->can('baseName')); return "desconhecido"; }
sub time_iso { my ($t) = @_; $t ||= time; my @t = gmtime($t); sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]); }
sub format_uptime { my ($s) = @_; my $d = int($s/86400); $s %= 86400; my $h = int($s/3600); $s %= 3600; my $m = int($s/60); return sprintf "%dd %02dh %02dm", $d, $h, $m; }

notify({title => "✅ Plugin Discord v$plugin_version Iniciado", description => "Modo de notificação: $CONFIG{notification_mode}.", simple_text => "✅ Plugin Discord v$plugin_version iniciado."});

1;
