-module(aestratum_client_generator_manager_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_MODULE, aestratum_client_generator_manager).
-define(NONCE_MODULE, aestratum_nonce).
-define(CLIENT_GENERATOR_WORKER_MODULE, aestratum_client_generator_worker).

-define(TEST_JOB_ID, <<"0102030405060708">>).
-define(TEST_TARGET, 16#ff0000000000000000000000000000000000000000000000000000000).
-define(TEST_BLOCK_HASH,
        <<"000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f">>).

client_generator_manager_test_() ->
    {foreach,
     fun() ->
             meck:new(?CLIENT_GENERATOR_WORKER_MODULE, [passthrough]),
             {ok, Pid} = ?TEST_MODULE:start_link(),
             Pid
     end,
     fun(_) ->
             ok = ?TEST_MODULE:stop(),
             meck:unload(?CLIENT_GENERATOR_WORKER_MODULE)
     end,
     [fun(_) -> add_and_del_worker() end,
      fun(_) -> generate(no_workers) end,
      fun(_) -> generate(single_worker, miner_nonce_exhausted) end,
      fun(_) -> generate(single_worker, started) end,
      fun(_) -> generate(single_worker, queued) end,
      fun(_) -> generate(multiple_workers, miner_nonce_exhausted) end,
      fun(_) -> generate(multiple_workers, started) end,
      fun(_) -> generate(multiple_workers, queued) end,
      fun(_) -> generate(multiple_workers, started_and_queued) end]}.

add_and_del_worker() ->
    [?_assertEqual(ok, ?TEST_MODULE:add(0, new_pid(), 1)),
     ?_assertEqual(ok, ?TEST_MODULE:del(0))].

generate(no_workers) ->
    T = <<"generate - no_workers">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 1, target => ?TEST_TARGET, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#112233445566, 6),
    [{T, ?_assertEqual({ok, #{started => {0, 0}, queued => {0, 0}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}].

generate(single_worker, miner_nonce_exhausted) ->
    T = <<"generate - single_worker, miner_nonce_exhausted">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 1, target => ?TEST_TARGET, empty_queue => true},
    %% Extra nonce takes up 7 bytes, only 1 byte is left for a worker.
    %% 1 byte are nonce values between 0 and 255 (so 256 nonce values).
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccddeeff00, 7),
    prep_workers([{0, new_pid(), 257, available}]),
    [{T, ?_assertEqual({error, miner_nonce_exhausted},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(single_worker, started) ->
    T = <<"generate - single_worker, started">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 2, target => ?TEST_TARGET, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#aabbccdd, 7),
    prep_workers([{0, new_pid(), 256, available}]),
    [{T, ?_assertEqual({ok, #{started => {1, 256}, queued => {0, 0}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(single_worker, queued) ->
    T = <<"generate - single_worker, queued">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 2, target => ?TEST_TARGET, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#ffffffffffff, 6),
    prep_workers([{0, new_pid(), 1, busy}]),
    [{T, ?_assertEqual({ok, #{started => {0, 0}, queued => {1, 1}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(multiple_workers, miner_nonce_exhausted) ->
    T = <<"generate - multiple_workers, miner_nonce_exhausted">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 1, target => ?TEST_TARGET, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#11223344556677, 7),
    prep_workers([{0, new_pid(), 100, available},
                  {1, new_pid(), 100, busy},
                  {2, new_pid(), 57, available}]),
    [{T, ?_assertEqual({error, miner_nonce_exhausted},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(multiple_workers, started) ->
    T = <<"generate - multiple_workers, started">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 2, target => ?TEST_TARGET, empty_queue => true},
    ExtraNonce = ?NONCE_MODULE:new(extra, 0, 4),
    prep_workers([{0, new_pid(), 10, available},
                  {1, new_pid(), 100, available},
                  {2, new_pid(), 50, available}]),
    [{T, ?_assertEqual({ok, #{started => {3, 160}, queued => {0, 0}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(multiple_workers, queued) ->
    T = <<"generate - multiple_workers, queued">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 2, target => ?TEST_TARGET, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 0, 4),
    prep_workers([{0, new_pid(), 10, busy},
                  {1, new_pid(), 100, busy},
                  {2, new_pid(), 50, busy}]),
    [{T, ?_assertEqual({ok, #{started => {0, 0}, queued => {3, 160}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}];
generate(multiple_workers, started_and_queued) ->
    T = <<"generate - multiple_workers, started_and_queued">>,
    Job = #{job_id => ?TEST_JOB_ID, block_hash => ?TEST_BLOCK_HASH,
            block_version => 2, target => ?TEST_TARGET, empty_queue => false},
    ExtraNonce = ?NONCE_MODULE:new(extra, 10000, 3),
    prep_workers([{0, new_pid(), 1111, busy},
                  {1, new_pid(), 2222, available},
                  {2, new_pid(), 3333, busy}]),
    [{T, ?_assertEqual({ok, #{started => {1, 2222}, queued => {2, 4444}}},
                       ?TEST_MODULE:generate(Job, ExtraNonce))}].

prep_workers(Workers) ->
    prep_workers(Workers, Workers).

prep_workers([{Id, Pid, Repeats, _Status} | Rest], Workers) ->
    ok = ?TEST_MODULE:add(Id, Pid, Repeats),
    prep_workers(Rest, Workers);
prep_workers([], Workers) ->
    meck:expect(?CLIENT_GENERATOR_WORKER_MODULE, generate,
                fun(Pid, _, _, _) ->
                        {_Id, Pid, Repeats, Status} = lists:keyfind(Pid, 2, Workers),
                        {worker_action(Status), Repeats}
                end).

worker_action(available) -> started;
worker_action(busy)      -> queued.

%% This is just to get a PID. The process itself is not important.
new_pid() ->
    spawn(fun() -> ok end).

