#    M              OOOOOOOO
#    A            OO--------OO
#    D          OO--------VVVVOO
#    E        OOVVVV------VVVVVVOO
#             OOVVVV------VVVVVVOO
#    B      OOVVVVVV--------VVVV--OO
#    Y      OOVVVVVV--------------OO
#         OO----------VVVVVV--------OO
#    O    OO--------VVVVVVVVVV------OO
#    V    OOVVVV----VVVVVVVVVV------OO
#    O    OOVVVVVV--VVVVVVVVVV--VV--OO
#    K      OOVVVV----VVVVVV--VVVVOO
#    O      OOVVVV------------VVVVOO
#    R        OOOO--------------OO
#    E            OO--------OOOO
#    !              OOOOOOOO
#    and... adapted by alisonrag e unknown

package LatamChecksum;

use strict;
use Plugins;
use Globals;
use Misc;
use AI;
use utf8;
use Network::Send ();
use Log           qw(message warning error debug);
use IO::Socket::INET;
use Time::HiRes qw(usleep);

my $counter = 0;
my $enabled = 0;
my $porta = undef;

my $CHECKSUM_HOST = '172.65.175.69';
my $CHECKSUM_PORT;
my $TIMEOUT = 1000;

BEGIN {
	print "\n=== Plugin LatamChecksum ===\n";
	print "Digite a porta de conexão LATAM (ex: 6901): ";
	$porta = <STDIN>;
	chomp $porta;

	if ($porta !~ /^\d+$/) {
		error "Porta inválida. Usando valor padrão 6901.\n";
		$porta = "6901";
	}

	message "[LatamChecksum] Porta configurada: $porta\n", "system";
}


Plugins::register('LatamChecksum', 'LATAM checksum plugin com porta dinâmica', \&onUnload);

my $hooks = Plugins::addHooks(
	['start3',                \&checkServer, undef],
);
my $base_hooks;

sub checkServer {
	my $master = $masterServers{ $config{master} };
	if ( grep { $master->{serverType} eq $_ } qw(ROla) ) {
		$base_hooks = Plugins::addHooks(
			[ 'serverDisconnect/fail',    \&serverDisconnect, undef ],
			[ 'serverDisconnect/success', \&serverDisconnect, undef ],
			[ 'Network::serverSend/pre',  \&serverSendPre,    undef ]
		);
	}
}

sub unload {
	Plugins::delHooks( $base_hooks );
	Plugins::delHooks( $hooks ) if ( $hooks );
}


BEGIN {
	print "\n=== Plugin LatamChecksum ===\n";
	print "Digite a porta para o servidor de checksum (ex: 6901): ";
	my $porta = <STDIN>;
	chomp $porta;

	if ($porta !~ /^\d+$/) {
		error "Porta inválida. Usando valor padrão 6901.\n";
		$CHECKSUM_PORT = 6901;
	} else {
		$CHECKSUM_PORT = $porta;
	}

	message "[LatamChecksum] Porta de checksum configurada: $CHECKSUM_PORT\n", "system";
}

	warning "COUNTER $counter\n", "latam";


	# Send data to server with current counter value
	my $packet = $data . pack("N", $counter); # Send data + counter
	
	unless (print $socket $packet) {
		error "LatamChecksum: Failed to send data to checksum server - $!\n";
		$socket->close();
		return 0;
	}
	
	# Increment counter after sending to socket
	$counter += 1;
	
	# Read checksum response
	my $response;
	my $bytes_read = sysread($socket, $response, 1); # Expecting 1 byte checksum
	$socket->close();
	
	unless (defined $bytes_read && $bytes_read == 1) {
		error "LatamChecksum: Failed to read checksum from server\n";
		return 0;
	}
	
	my $checksum = unpack("C", $response);
	warning "LatamChecksum: Received checksum $checksum for packet length " . length($data) . "\n", "latam";
	
	return $checksum;
}

sub serverDisconnect {
	warning "Checksum disabled on server disconnect.\n";
	$enabled = 0;
	$counter = 0;
}

sub serverSendPre {
	my ( $self, $args ) = @_;
	my $msg       = $args->{msg};
	my $messageID = uc( unpack( "H2", substr( $$msg, 1, 1 ) ) ) . uc( unpack( "H2", substr( $$msg, 0, 1 ) ) );

	if ( ref($::net) eq 'Network::XKore' ) {
		return;
	}

	if ( $counter == 0 ) {
		if ( $messageID eq '0B1C' ) {
			warning "Checksum enabled on first.\n";
			$enabled = 1;
		}

		if ( $messageID eq $messageSender->{packet_lut}{map_login} ) {
			warning "Checksum enabled on map login.\n";
			$enabled = 1;
			$messageSender->sendPing();
		}
	}

	if ( $::net->getState() >= 4 ) {
		$$msg .= pack( "C", calc_checksum( $$msg ) );
		warning "Com checksum: " . unpack("H*", $$msg) . "\n", "latam";
	}
}

1;