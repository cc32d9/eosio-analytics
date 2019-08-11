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

my $port = 8800;

my $dsn = 'DBI:MariaDB:database=eos_analytics;host=localhost';
my $db_user = 'eos_analytics';
my $db_password = 'guugh3Ei';
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

my $sth_add_transfer = $dbh->prepare
    ('INSERT INTO EOSIO_TRANSFERS ' .
     '(seq, block_num, block_time, trx_id, ' .
     'contract, currency, amount, tx_from, tx_to, memo) ' .
     'VALUES(?,?,?,?,?,?,?,?,?,?)');

my $sth_add_vote = $dbh->prepare
    ('INSERT INTO EOSIO_VOTES ' .
     '(seq, block_num, block_time, trx_id, ' .
     'voter, bp) ' .
     'VALUES(?,?,?,?,?,?)');

my $sth_add_proxy_vote = $dbh->prepare
    ('INSERT INTO EOSIO_PROXY_VOTES ' .
     '(seq, block_num, block_time, trx_id, ' .
     'voter, proxy) ' .
     'VALUES(?,?,?,?,?,?)');


my $sth_add_delegatebw = $dbh->prepare
    ('INSERT INTO EOSIO_DELEGATEBW ' .
     '(seq, block_num, block_time, trx_id, ' .
     'owner, receiver, delegate, transfer, cpu, net) ' .
     'VALUES(?,?,?,?,?,?,?,?,?,?)');


my $sth_wipe_transfers = $dbh->prepare
    ('DELETE FROM EOSIO_TRANSFERS WHERE block_num >= ? AND block_num < ?');

my $sth_wipe_votes = $dbh->prepare
    ('DELETE FROM EOSIO_VOTES WHERE block_num >= ? AND block_num < ?');

my $sth_wipe_proxy_votes = $dbh->prepare
    ('DELETE FROM EOSIO_PROXY_VOTES WHERE block_num >= ? AND block_num < ?');

my $sth_wipe_delegatebw = $dbh->prepare
    ('DELETE FROM EOSIO_DELEGATEBW WHERE block_num >= ? AND block_num < ?');


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
        $sth_wipe_transfers->execute($block_num, $endblock);
        $sth_wipe_votes->execute($block_num, $endblock);
        $sth_wipe_proxy_votes->execute($block_num, $endblock);
        $sth_wipe_delegatebw->execute($block_num, $endblock);
        $dbh->commit();
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
            
            my $tx = {'block_num' => $data->{'block_num'},
                      'block_time' => $block_time,
                      'trx_id' => $trace->{'id'}};

            foreach my $atrace (@{$trace->{'action_traces'}})
            {
                process_atrace($tx, $atrace);
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


sub process_atrace
{
    my $tx = shift;
    my $atrace = shift;

    my $act = $atrace->{'act'};
    my $contract = $act->{'account'};
    my $receipt = $atrace->{'receipt'};
    
    if( $receipt->{'receiver'} eq $contract )
    {
        my $seq = $receipt->{'global_sequence'};
        my $aname = $act->{'name'};

        my $data = $act->{'data'};
        return unless ( ref($data) eq 'HASH' );
        
        if( ($aname eq 'transfer' or $aname eq 'issue') and 
            defined($data->{'quantity'}) and defined($data->{'to'}) )
        {
            my ($amount, $currency) = split(/\s+/, $data->{'quantity'});
            if( defined($amount) and defined($currency) and
                $amount =~ /^[0-9.]+$/ and $currency =~ /^[A-Z]{1,7}$/ )
            {
                $sth_add_transfer->execute
                    (
                     $seq,
                     $tx->{'block_num'},
                     $tx->{'block_time'},
                     $tx->{'trx_id'},
                     $contract,
                     $currency,
                     $amount,
                     $data->{'from'},
                     $data->{'to'},
                     $data->{'memo'}
                    );
            }
        }
        elsif( $contract eq 'eosio' )
        {
            if( $aname eq 'delegatebw' )
            {
                my ($cpu, $curr1) = split(/\s+/, $data->{'stake_cpu_quantity'});
                my ($net, $curr2) = split(/\s+/, $data->{'stake_net_quantity'});
                
                $sth_add_delegatebw->execute
                    (
                     $seq,
                     $tx->{'block_num'},
                     $tx->{'block_time'},
                     $tx->{'trx_id'},
                     $data->{'from'},
                     $data->{'receiver'},
                     1,
                     $data->{'transfer'} ? 1:0,
                     $cpu,
                     $net
                    );
            }
            elsif( $aname eq 'undelegatebw' )
            {
                my ($cpu, $curr1) = split(/\s+/, $data->{'unstake_cpu_quantity'});
                my ($net, $curr2) = split(/\s+/, $data->{'unstake_net_quantity'});
                
                $sth_add_delegatebw->execute
                    (
                     $seq,
                     $tx->{'block_num'},
                     $tx->{'block_time'},
                     $tx->{'trx_id'},
                     $data->{'from'},
                     $data->{'receiver'},
                     0,
                     0,
                     $cpu,
                     $net
                    );
            }
            elsif( $aname eq 'voteproducer' )
            {
                if( $data->{'proxy'} eq '' )
                {
                    foreach my $bp (@{$data->{'producers'}})
                    {
                        $sth_add_vote->execute
                            (
                             $seq,
                             $tx->{'block_num'},
                             $tx->{'block_time'},
                             $tx->{'trx_id'},
                             $data->{'voter'},
                             $bp
                            );
                    }
                }
                else
                {
                    $sth_add_proxy_vote->execute
                        (
                         $seq,
                         $tx->{'block_num'},
                         $tx->{'block_time'},
                         $tx->{'trx_id'},
                         $data->{'voter'},
                         $data->{'proxy'}
                        );
                }
            }
        }
    }    
}



    
        


   
