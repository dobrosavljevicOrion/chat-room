-module(chat_server).

-include("../include/chat.hrl").

-compile(export_all).

start() ->
    register(chat_server, spawn(?MODULE, init, [])).

start_link() ->
    register(chat_server, spawn_link(?MODULE, init, [])).

init() ->
    process_flag(trap_exit, true),
    loop([]).

loop(State) ->
    receive
        shutdown ->
            io:format("Server shutting down~n"),
            ok;
        Unknown ->
            io:format("Unknown message: ~p~n",[Unknown]),
            loop(State)
    end.

terminate() -> 
    chat_server ! shutdown.