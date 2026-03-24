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
        {Pid, Ref, {join, Name}} ->
            case lists:any(fun(U) -> U#user.name =:= Name end, State) of
                true ->
                    Pid ! {Ref, {error, username_taken}},
                    loop(State);
                false ->
                    User = #user{name = Name, pid = Pid},
                    link(Pid),
                    lists:foreach(fun(U) ->
                        U#user.pid ! {user_joined, Name}
                    end, State),
                    Pid ! {Ref, {ok, joined}},
                    loop([User | State])
            end;
        shutdown ->
            io:format("Server shutting down~n"),
            ok;
        Unknown ->
            io:format("Unknown message: ~p~n",[Unknown]),
            loop(State)
    end.

terminate() -> 
    chat_server ! shutdown.

join(Name) ->
    Ref = make_ref(),
    chat_server ! {self(), Ref, {join, Name}},
    receive
        {Ref, Reply} ->
            Reply
    after 5000 ->
        {error, timeout}
    end.