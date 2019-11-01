# install dependencies:
#  sudo apt install cpanminus libjson-xs-perl libjson-perl libmysqlclient-dev libdbi-perl
#  sudo cpanm Net::WebSocket::Server
#  sudo cpanm DBD::MariaDB

use strict;
use warnings;
use JSON;
use Getopt::Long;
use DBI;

use Net::WebSocket::Server;
use Protocol::WebSocket::Frame;

$Protocol::WebSocket::Frame::MAX_PAYLOAD_SIZE = 100*1024*1024;
$Protocol::WebSocket::Frame::MAX_FRAGMENTS_AMOUNT = 102400;
    
$| = 1;

my $port = 8101;

my $dsn = 'DBI:MariaDB:database=activity;host=localhost';
my $db_user = 'activity';
my $db_password = 'sdcrqewirxs';
my $commit_every = 100;
my $endblock = 2**32 - 1;
    
my $ok = GetOptions
    ('port=i'    => \$port,
     'ack=i'     => \$commit_every,
     'endblock=i'  => \$endblock,
     'dsn=s'     => \$dsn,
     'dbuser=s'  => \$db_user,
     'dbpw=s'    => \$db_password,
    );


if( not $ok or scalar(@ARGV) > 0 )
{
    print STDERR "Usage: $0 [options...]\n",
        "Options:\n",
        "  --port=N           \[$port\] TCP port to listen to websocket connection\n",
        "  --ack=N            \[$commit_every\] Send acknowledgements every N blocks\n",
        "  --endblock=N       \[$endblock\] Stop before given block\n",
        "  --dsn=DSN          \[$dsn\]\n",
        "  --dbuser=USER      \[$db_user\]\n",
        "  --dbpw=PASSWORD    \[$db_password\]\n";
    exit 1;
}


my $dbh = DBI->connect($dsn, $db_user, $db_password,
                       {'RaiseError' => 1, AutoCommit => 0,
                        mariadb_server_prepare => 1});
die($DBI::errstr) unless $dbh;

my $sth_add_currbal = $dbh->prepare
    ('INSERT INTO CURRENCY_BAL ' .
     '(account_name, contract, currency, amount) ' .
     'VALUES(?,?,?,?) ' .
     'ON DUPLICATE KEY UPDATE amount=?');

my $sth_del_currbal = $dbh->prepare
    ('DELETE FROM CURRENCY_BAL WHERE ' .
     'account_name=? AND contract=? AND currency=?');


my $sth_add_account = $dbh->prepare
    ('INSERT IGNORE INTO ACCOUNTS ' .
     '(account_name) ' .
     'VALUES(?)');

my $sth_inc_authcnt = $dbh->prepare
    ('INSERT INTO AUTH_COUNTER ' .
     '(account_name, auth_c) ' .
     'VALUES(?,1) ' .
     'ON DUPLICATE KEY UPDATE auth_c=auth_c+1');


my $committed_block = 0;
my $uncommitted_block = 0;
my $json = JSON->new;

Net::WebSocket::Server->new(
    listen => $port,
    on_connect => sub {
        my ($serv, $conn) = @_;
        $conn->on(
            'binary' => sub {
                my ($conn, $msg) = @_;
                my ($msgtype, $opts, $js) = unpack('VVa*', $msg);
                my $data = eval {$json->decode($js)};
                if( $@ )
                {
                    print STDERR $@, "\n\n";
                    print STDERR $js, "\n";
                    exit;
                } 
                
                my $ack = process_data($msgtype, $data);
                if( $ack > 0 )
                {
                    $conn->send_binary(sprintf("%d", $ack));
                    print STDERR "ack $ack\n";
                }

                if( $ack >= $endblock )
                {
                    print STDERR "Reached end block\n";
                    exit(0);
                }
            },
            'disconnect' => sub {
                my ($conn, $code) = @_;
                print STDERR "Disconnected: $code\n";
                $dbh->rollback();
                $committed_block = 0;
                $uncommitted_block = 0;
            },
            
            );
    },
    )->start;


sub process_data
{
    my $msgtype = shift;
    my $data = shift;

    if( $msgtype == 1001 ) # CHRONICLE_MSGTYPE_FORK
    {
        my $block_num = $data->{'block_num'};
        print STDERR "fork at $block_num\n";
        $committed_block = $block_num-1;
        $uncommitted_block = 0;
        return $block_num;
    }
    elsif( $msgtype == 1003 ) # CHRONICLE_MSGTYPE_TX_TRACE
    {
        my $trace = $data->{'trace'};
        if( $trace->{'status'} eq 'executed' )
        {
            my $block_time = $data->{'block_timestamp'};
            $block_time =~ s/T/ /;
            
            foreach my $atrace (@{$trace->{'action_traces'}})
            {
                my $act = $atrace->{'act'};
                my $contract = $act->{'account'};
                my $receipt = $atrace->{'receipt'};
                
                if( $receipt->{'receiver'} eq $contract )
                {
                    foreach my $auth (@{$act->{'authorization'}})
                    {
                        $sth_inc_authcnt->execute($auth->{'actor'});
                    }
                }
            }
        }
    }
    elsif( $msgtype == 1007 ) # CHRONICLE_MSGTYPE_TBL_ROW
    {
        my $kvo = $data->{'kvo'};
        if( ref($kvo->{'value'}) eq 'HASH' )
        {
            if( $kvo->{'table'} eq 'accounts' )
            {
                if( defined($kvo->{'value'}{'balance'}) and
                    $kvo->{'scope'} =~ /^[a-z0-5.]+$/ )
                {
                    my $bal = $kvo->{'value'}{'balance'};
                    if( $bal =~ /^([0-9.]+) ([A-Z]{1,7})$/ )
                    {
                        my $amount = $1;
                        my $currency = $2;

                        if( $data->{'added'} eq 'true' )
                        {
                            $sth_add_currbal->execute
                                ($kvo->{'scope'}, $kvo->{'code'}, $currency, $amount);
                        }
                        else
                        {
                            $sth_del_currbal->execute
                                ($kvo->{'scope'}, $kvo->{'code'}, $currency);
                        }
                    }
                }
            }
        }
    }
    elsif( $msgtype == 1009 ) # CHRONICLE_MSGTYPE_RCVR_PAUSE
    {
        if( $uncommitted_block > $committed_block )
        {
            $dbh->commit();
            $committed_block = $uncommitted_block;
            return $committed_block;
        }
    }
    elsif( $msgtype == 1010 ) # CHRONICLE_MSGTYPE_BLOCK_COMPLETED
    {
        $uncommitted_block = $data->{'block_num'};
        if( $uncommitted_block - $committed_block >= $commit_every or
            $uncommitted_block >= $endblock )
        {
            $dbh->commit();
            $committed_block = $uncommitted_block;
            return $committed_block;
        }
    }

    return 0;
}


