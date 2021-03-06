%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(qilr_analyzer_sup).
-behaviour(supervisor).
-export([start_link/0, init/1, stop/1]).
-export([new_conn/0]).

new_conn() ->
    supervisor:start_child(?MODULE, []).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_S) -> ok.

%% @private
init([]) ->
    {ok,
     {{simple_one_for_one, 10, 10},
      [{undefined,
        {qilr_analyzer, start_link, []},
        temporary, 2000, worker, [qilr_analyzer]}]}}.
