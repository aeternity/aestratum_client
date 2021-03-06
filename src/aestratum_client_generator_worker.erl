-module(aestratum_client_generator_worker).

-behaviour(gen_server).

%% API.
-export([start_link/1,
         stop/1,
         generate/4,
         status/1
        ]).

-export([pid/1,
         job_id/1,
         block_hash/1,
         block_version/1,
         target/1,
         extra_nonce/1,
         miner_nonce/1
        ]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2
        ]).

-include("aestratum_client_log.hrl").

%% Internal exports.
-export([worker_process/7]).

-export_type([worker/0]).

-define(CLIENT_HANDLER, aestratum_client_handler).


-type miner()           :: aestratum_client_miner:miner().

-type job_id()          :: binary().

-type block_hash()      :: aestratum_miner:block_hash().

-type block_version()   :: aestratum_miner:block_version().

-type empty_queue()     :: boolean().

-type target()          :: aestratum_miner:target().

-type extra_nonce()     :: aestratum_nonce:part_nonce().

-type miner_nonce()     :: aestratum_nonce:part_nonce().

-type repeats()         :: aestratum_miner:repeats().

-type monitor()         :: reference().

-type timer()           :: reference().

-type job()             :: #{job_id        => job_id(),
                             block_hash    => block_hash(),
                             block_version => block_version(),
                             target        => target(),
                             empty_queue   => empty_queue()}.

-record(worker, {
          pid           :: pid(),
          job_id        :: job_id(),
          block_hash    :: block_hash(),
          block_version :: block_version(),
          target        :: target(),
          extra_nonce   :: extra_nonce(),
          miner_nonce   :: miner_nonce(),
          monitor       :: monitor(),
          timer         :: timer()
         }).

-opaque worker()        :: #worker{}.

%% TODO queue of jobs
-record(state, {
          miner         :: miner(),
          worker        :: worker()
                         | undefined
         }).

%% API.

-spec start_link(miner()) -> {ok, pid()}.
start_link(Miner) ->
    gen_server:start_link(?MODULE, Miner, []).

-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

-spec generate(pid(), job(), extra_nonce(), miner_nonce()) ->
    {started | queued, repeats()}.
generate(Pid, Job, ExtraNonce, MinerNonce) ->
    gen_server:call(Pid, {generate, Job, ExtraNonce, MinerNonce}).

-spec pid(worker()) -> pid().
pid(#worker{pid = Pid}) ->
    Pid.

-spec job_id(worker()) -> job_id().
job_id(#worker{job_id = JobId}) ->
    JobId.

-spec block_hash(worker()) -> block_hash().
block_hash(#worker{block_hash = BlockHash}) ->
    BlockHash.

-spec block_version(worker()) -> block_version().
block_version(#worker{block_version = BlockVersion}) ->
    BlockVersion.

-spec target(worker()) -> target().
target(#worker{target = Target}) ->
    Target.

-spec extra_nonce(worker()) -> extra_nonce().
extra_nonce(#worker{extra_nonce = ExtraNonce}) ->
    ExtraNonce.

-spec miner_nonce(worker()) -> miner_nonce().
miner_nonce(#worker{miner_nonce = MinerNonce}) ->
    MinerNonce.

-spec status(pid()) -> term().
status(Pid) ->
    gen_server:call(Pid, status).

%% gen_server callbacks.

init(Miner) ->
    process_flag(trap_exit, true),
    MinerId = aestratum_client_miner:id(Miner),
    Config = aestratum_client_miner:config(Miner),
    Repeats = aestratum_miner:repeats(Config),
    aestratum_client_generator_manager:add(MinerId, self(), Repeats),
    {ok, #state{miner = Miner}}.

handle_call({generate, Job, ExtraNonce, MinerNonce}, _From, State) ->
    Action = abort_running_worker(Job),
    {ok, Reply, State1} =
        handle_generate(Action, Job, ExtraNonce, MinerNonce, State),
    {reply, Reply, State1};
handle_call(status, _From, #state{miner = Miner, worker = Worker} = State) ->
    {reply, {ok, #{miner => Miner, worker => Worker}}, State}.

handle_cast(_Req, State) ->
    {noreply, State}.

handle_info({worker_reply, Reply}, State) ->
    {noreply, handle_reply(Reply, State)};
handle_info(worker_timeout, State) ->
    {noreply, handle_timeout(State)};
handle_info({'DOWN', Ref, process, _Pid, Rsn}, State) ->
    {noreply, handle_down(Ref, Rsn, State)}.

terminate(Rsn, #state{miner = Miner, worker = Worker}) ->
    MinerId = aestratum_client_miner:id(Miner),
    aestratum_client_generator_manager:del(MinerId),
    if Worker =/= undefined -> kill_worker(Worker, Rsn); true -> ok end,
    ok.

%% Internal functions.

handle_generate(abort, Job, ExtraNonce, MinerNonce,
                #state{miner = Miner, worker = #worker{} = Worker} = State) ->
    kill_worker(Worker, aborted),
    {Worker1, Repeats} = spawn_worker(Miner, Job, ExtraNonce, MinerNonce, 30000),
    {ok, {started, Repeats}, State#state{worker = Worker1}};
handle_generate(_Action, Job, ExtraNonce, MinerNonce,
                #state{miner = Miner, worker = undefined} = State) ->
    {Worker1, Repeats} = spawn_worker(Miner, Job, ExtraNonce, MinerNonce, 30000),
    {ok, {started, Repeats}, State#state{worker = Worker1}};
handle_generate(keep, _Job, _ExtraNonce, _MinerNonce,
                #state{miner = Miner, worker = #worker{}} = State) ->
    Config = aestratum_client_miner:config(Miner),
    {ok, {queued, aestratum_miner:repeats(Config)}, State}.

handle_reply(Reply, #state{worker = #worker{monitor = Monitor,
                                            timer = Timer}} = State) ->
    cancel_monitor(Monitor),
    cancel_timer(Timer),
    maybe_notify(Reply, State),
    State#state{worker = undefined}.

handle_timeout(#state{worker = #worker{} = Worker} = State) ->
    kill_worker(Worker, timeout),
    State#state{worker = undefined};
handle_timeout(#state{worker = undefined} = State) ->
    State.

handle_down(Ref, _Rsn, #state{worker = #worker{monitor = Ref,
                                               timer = Timer}} = State) ->
    cancel_timer(Timer),
    State#state{worker = undefined}.

spawn_worker(Miner, #{job_id := JobId, block_hash := BlockHash,
                      block_version := BlockVersion, target := Target},
             ExtraNonce, MinerNonce, Timeout) ->
    Nonce = aestratum_nonce:merge(ExtraNonce, MinerNonce),
    Instance = aestratum_client_miner:instance(Miner),
    Config = aestratum_client_miner:config(Miner),
    {Pid, Monitor} =
        spawn_monitor(?MODULE, worker_process,
                      [self(), BlockHash, BlockVersion, Target, Nonce,
                       Instance, Config]),
    ?INFO("spawn_worker, pid: ~p, block_hash: ~p, block_version: ~p, "
          "target: ~p, nonce: ~p, instance: ~p",
          [Pid, BlockHash, BlockVersion, aestratum_target:to_hex(Target),
           aestratum_nonce:value(Nonce), Instance]),
    {#worker{pid = Pid, job_id = JobId, block_hash = BlockHash,
             block_version = BlockVersion, target = Target,
             extra_nonce = ExtraNonce, miner_nonce = MinerNonce,
             monitor = Monitor, timer = set_timer(Timeout)},
     aestratum_miner:repeats(Config)}.

worker_process(Parent, BlockHash, BlockVersion, Target, Nonce, Instance, Config) ->
    case aestratum_miner:generate(BlockHash, BlockVersion, Target, Nonce,
                                  Instance, Config) of
        {ok, {Nonce1, Pow} = Reply} ->
            ?INFO("worker_found_solution, pid: ~p, nonce: ~p, pow: ~p",
                  [self(), Nonce1, Pow]),
            make_worker_reply(Parent, Reply);
        {error, no_solution = Reply} ->
            ?INFO("worker_no_solution, pid: ~p", [self()]),
            make_worker_reply(Parent, Reply);
        {error, {runtime, Rsn}} ->
            ?ERROR("worker_error, reason: ~p, pid: ~p", [Rsn, self()]),
            make_worker_reply(Parent, runtime_error)
    end.

make_worker_reply(Parent, Reply) ->
    Parent ! {worker_reply, Reply}.

kill_worker(#worker{pid = Pid, monitor = Monitor, timer = Timer}, Rsn) ->
    cancel_monitor(Monitor),
    cancel_timer(Timer),
    exit(Pid, shutdown),
    ?INFO("kill_worker, reason: ~p, pid: ~p", [Rsn, Pid]),
    flush_worker_reply().

flush_worker_reply() ->
    receive {worker_reply, _Res} -> ok
    after 0 -> ok end.

abort_running_worker(#{empty_queue := true})  -> abort;
abort_running_worker(#{empty_queue := false}) -> keep.

maybe_notify({Nonce, Pow}, State) ->
    notify(Nonce, Pow, State);
maybe_notify(_Other, _State) ->
    ok.

notify(Nonce, Pow,
       #state{worker = #worker{job_id = JobId, extra_nonce = ExtraNonce}}) ->
    Nonce1 = aestratum_nonce:new(Nonce),
    ExtraNonceNBytes = aestratum_nonce:nbytes(ExtraNonce),
    {ExtraNonce, MinerNonce} =
        aestratum_nonce:split({extra, ExtraNonceNBytes}, Nonce1),
    Share = #{job_id => JobId, miner_nonce => MinerNonce, pow => Pow},
    ?CLIENT_HANDLER ! {miner, #{event => found_share, share => Share}}.

set_timer(Timeout) when Timeout =/= infinity ->
    erlang:send_after(Timeout, self(), worker_timeout);
set_timer(infinity) ->
    undefined.

cancel_timer(Timer) when is_reference(Timer) ->
    erlang:cancel_timer(Timer);
cancel_timer(undefined) ->
    ok.

cancel_monitor(Monitor) when is_reference(Monitor) ->
    demonitor(Monitor, [flush]).
