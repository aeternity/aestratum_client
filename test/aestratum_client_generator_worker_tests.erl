-module(aestratum_client_generator_worker_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_MODULE, aestratum_client_generator_worker).
-define(NONCE_MODULE, aestratum_nonce).
-define(MINER_MODULE, aestratum_miner).
-define(CLIENT_MINER_MODULE, aestratum_client_miner).
-define(CLIENT_GENERATOR_MANAGER_MODULE, aestratum_client_generator_manager).
-define(DUMMY_SUBSCRIBER_MODULE, aestratum_dummy_subscriber).
-define(CLIENT_HANDLER_MODULE, aestratum_client_handler).

-define(TEST_MINER_ID, 0).
-define(TEST_MINER_INSTANCE, undefined).
-define(TEST_MINER_REPEATS, 5).
-define(TEST_MINER_CONFIG,
        ?MINER_MODULE:config(<<"mean29-generic">>, <<"aecuckoo">>, <<>>,
                             false, ?TEST_MINER_REPEATS, 29, undefined)).
-define(TEST_JOB_ID1, <<"0102030405060708">>).
-define(TEST_JOB_ID2, <<"0a0b0c0d0e0fffff">>).
-define(TEST_TARGET1, 16#ff0000000000000000000000000000000000000000000000000000000).
-define(TEST_TARGET2, 16#fffffeee0000000000000000000000000000000000000000000000000).
-define(TEST_BLOCK_HASH1,
        <<"000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f">>).
-define(TEST_BLOCK_HASH2,
        <<"fffabcdefabcd60708090a0b0c0d0e0f000102030405060708090a0b00000000">>).

config() ->
    ?CLIENT_MINER_MODULE:new(
       ?TEST_MINER_ID, ?TEST_MINER_INSTANCE, ?TEST_MINER_CONFIG).

client_generator_worker_test_() ->
    {foreach,
     fun() ->
             meck:new(?MINER_MODULE, [passthrough]),
             meck:new(?CLIENT_GENERATOR_MANAGER_MODULE, [passthrough]),
             meck:expect(?CLIENT_GENERATOR_MANAGER_MODULE, add, fun(_, _, _) -> ok end),
             {ok, _} = ?DUMMY_SUBSCRIBER_MODULE:start_link(?CLIENT_HANDLER_MODULE),
             {ok, Pid} = ?TEST_MODULE:start_link(config()),
             Pid
     end,
     fun(Pid) ->
             meck:expect(?CLIENT_GENERATOR_MANAGER_MODULE, del, fun(_) -> ok end),
             ok = ?TEST_MODULE:stop(Pid),
             ok = ?DUMMY_SUBSCRIBER_MODULE:stop(?CLIENT_HANDLER_MODULE),
             meck:unload(?CLIENT_GENERATOR_MANAGER_MODULE),
             meck:unload(?MINER_MODULE)
     end,
     [{with, [fun init/1]},
      {with, [fun generate_when_no_worker_abort_worker_keep_mining/1]},
      {with, [fun generate_when_no_worker_abort_worker_no_solution/1]},
      {with, [fun generate_when_no_worker_abort_worker_runtime_error/1]},
      {with, [fun generate_when_no_worker_abort_worker_valid_solution/1]},
      {with, [fun generate_when_no_worker_keep_worker_keep_mining/1]},
      {with, [fun generate_when_no_worker_keep_worker_no_solution/1]},
      {with, [fun generate_when_no_worker_keep_worker_runtime_error/1]},
      {with, [fun generate_when_no_worker_keep_worker_valid_solution/1]},
      {with, [fun generate_when_worker_abort_worker_keep_mining/1]},
      {with, [fun generate_when_worker_abort_worker_no_solution/1]},
      {with, [fun generate_when_worker_abort_worker_runtime_error/1]},
      {with, [fun generate_when_worker_abort_worker_valid_solution/1]},
      {with, [fun generate_when_worker_keep_worker_keep_mining/1]},
      {with, [fun generate_when_worker_keep_worker_no_solution/1]},
      {with, [fun generate_when_worker_keep_worker_runtime_error/1]},
      {with, [fun generate_when_worker_keep_worker_valid_solution/1]}]}.

init(Pid) ->
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),
    ?assertEqual(?TEST_MINER_ID, ?CLIENT_MINER_MODULE:id(Miner)),
    ?assertEqual(?TEST_MINER_INSTANCE, ?CLIENT_MINER_MODULE:instance(Miner)),
    ?assertEqual(?TEST_MINER_CONFIG, ?CLIENT_MINER_MODULE:config(Miner)),
    ?assertEqual(undefined, Worker).

generate_when_no_worker_abort_worker_keep_mining(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 10, 4),

    mock_generate(keep_mining),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                  ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_abort_worker_no_solution(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    mock_generate(return_no_solution),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_abort_worker_runtime_error(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    mock_generate(return_runtime_error),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_abort_worker_valid_solution(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    {MinerNonce1, Solution} =
        mock_generate(return_valid_solution, ExtraNonce, MinerNonce),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    Event = {miner, #{job_id => ?TEST_JOB_ID1,
                      miner_nonce => MinerNonce1,
                      solution => Solution}},
    ?assertEqual({ok, [Event]}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_keep_worker_keep_mining(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 2, target => ?TEST_TARGET1, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffff, 3),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 5),

    mock_generate(keep_mining),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(2, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_keep_worker_no_solution(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    mock_generate(return_no_solution),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_keep_worker_runtime_error(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    mock_generate(return_runtime_error),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_no_worker_keep_worker_valid_solution(Pid) ->
    Job = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
            block_version => 1, target => ?TEST_TARGET1, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffff, 4),
    MinerNonce = ?NONCE_MODULE:new(miner, 0, 4),

    {MinerNonce1, Solution} =
        mock_generate(return_valid_solution, ExtraNonce, MinerNonce),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    Event = {miner, #{job_id => ?TEST_JOB_ID1,
                      miner_nonce => MinerNonce1,
                      solution => Solution}},
    ?assertEqual({ok, [Event]}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_abort_worker_keep_mining(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => true},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(keep_mining),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID2, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH2, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET2, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce2, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_abort_worker_no_solution(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => true},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(return_no_solution),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_abort_worker_runtime_error(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => true},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(return_runtime_error),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_abort_worker_valid_solution(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => true},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    {MinerNonce3, Solution} =
        mock_generate(return_valid_solution, ExtraNonce, MinerNonce2),
    ?assertEqual({started, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(undefined, Worker),

    Event = {miner, #{job_id => ?TEST_JOB_ID2,
                      miner_nonce => MinerNonce3,
                      solution => Solution}},
    ?assertEqual({ok, [Event]}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_keep_worker_keep_mining(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => false},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(keep_mining),
    ?assertEqual({queued, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce1, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_keep_worker_no_solution(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => false},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(return_no_solution),
    ?assertEqual({queued, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce1, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_keep_worker_runtime_error(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => false},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    mock_generate(return_runtime_error),
    ?assertEqual({queued, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce1, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

generate_when_worker_keep_worker_valid_solution(Pid) ->
    Job1 = #{job_id => ?TEST_JOB_ID1, block_hash => ?TEST_BLOCK_HASH1,
             block_version => 1, target => ?TEST_TARGET1, empty_queue => true},
    MinerNonce1 = ?NONCE_MODULE:new(miner, 0, 3),
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddee, 5),
    prep_mininig_worker(Pid, Job1, ExtraNonce, MinerNonce1),

    Job2 = #{job_id => ?TEST_JOB_ID2, block_hash => ?TEST_BLOCK_HASH2,
             block_version => 1, target => ?TEST_TARGET2, empty_queue => false},
    MinerNonce2 = ?NONCE_MODULE:new(miner, 111, 3),

    {_MinerNonce3, _Solution} =
        mock_generate(return_valid_solution, ExtraNonce, MinerNonce2),
    ?assertEqual({queued, ?TEST_MINER_REPEATS},
                 ?TEST_MODULE:generate(Pid, Job2, ExtraNonce, MinerNonce2)),
    timer:sleep(100),
    {ok, #{miner := Miner, worker := Worker}} = ?TEST_MODULE:status(Pid),

    check_miner(Miner),

    ?assertEqual(?TEST_JOB_ID1, ?TEST_MODULE:job_id(Worker)),
    ?assertEqual(?TEST_BLOCK_HASH1, ?TEST_MODULE:block_hash(Worker)),
    ?assertEqual(1, ?TEST_MODULE:block_version(Worker)),
    ?assertEqual(?TEST_TARGET1, ?TEST_MODULE:target(Worker)),
    ?assertEqual(ExtraNonce, ?TEST_MODULE:extra_nonce(Worker)),
    ?assertEqual(MinerNonce1, ?TEST_MODULE:miner_nonce(Worker)),

    ?assertEqual({ok, []}, ?DUMMY_SUBSCRIBER_MODULE:events(?CLIENT_HANDLER_MODULE)).

check_miner(Miner) ->
    ?assertEqual(?TEST_MINER_ID, ?CLIENT_MINER_MODULE:id(Miner)),
    ?assertEqual(?TEST_MINER_INSTANCE, ?CLIENT_MINER_MODULE:instance(Miner)),
    ?assertEqual(?TEST_MINER_CONFIG, ?CLIENT_MINER_MODULE:config(Miner)).

prep_mininig_worker(Pid, Job, ExtraNonce, MinerNonce) ->
    mock_generate(keep_mining),
    {started, _} = ?TEST_MODULE:generate(Pid, Job, ExtraNonce, MinerNonce),
    timer:sleep(100),
    ok.

mock_generate(keep_mining) ->
    meck:expect(?MINER_MODULE, generate,
                fun(_, _, _, _, _, _) ->
                        timer:sleep(30000)
                end);
mock_generate(return_no_solution) ->
    meck:expect(?MINER_MODULE, generate,
                fun(_, _, _, _, _, _) ->
                        {error, no_solution}
                end);
mock_generate(return_runtime_error) ->
    meck:expect(?MINER_MODULE, generate,
                fun(_, _, _, _, _, _) ->
                        {error, {runtime, some_reason}}
                end).

mock_generate(return_valid_solution, ExtraNonce, MinerNonce) ->
    MinerNonceNBytes = ?NONCE_MODULE:nbytes(MinerNonce),
    MinerNonceValue = ?NONCE_MODULE:value(MinerNonce),
    %% MinerNonce1 simulates that on the 2nd attempt there was a solution found.
    %% The first attempt was with MinerNonce.
    MinerNonce1 = ?NONCE_MODULE:new(miner, MinerNonceValue + 1, MinerNonceNBytes),
    Nonce = ?NONCE_MODULE:merge(ExtraNonce, MinerNonce1),
    Solution = lists:seq(1, 42),
    meck:expect(?MINER_MODULE, generate,
                fun(_, _, _, _, _, _) ->
                        {ok, {?NONCE_MODULE:value(Nonce), Solution}}
                end),
    {MinerNonce1, Solution}.

