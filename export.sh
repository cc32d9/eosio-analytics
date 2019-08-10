for ((i=0; i<560; i++))
do
    start=`expr $i \* 100000`
    end=`expr \( $i + 1 \) \* 100000 - 1`
    for t in EOSIO_DELEGATEBW EOSIO_PROXY_VOTES EOSIO_TRANSFERS EOSIO_VOTES
    do
        sudo mysql --batch --database=eos_analytics \
             --execute="select * from $t where block_num >= $start and block_num <= $end" >$t.`printf '%.9d' $start`
    done
done
