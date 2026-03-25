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
        {'EXIT', Pid, Reason} ->
            {RemovedName, NewState} = remove_user_by_pid(Pid, State),
            case RemovedName of
                not_found ->
                    io:format("Received EXIT from unknown pid ~p, reason: ~p~n", [Pid, Reason]),
                    loop(State);
                _ ->
                    lists:foreach(fun(U) ->
                        U#user.pid ! {user_disconnected, RemovedName}
                    end, NewState),
                    io:format("User ~s crashes/exits.~n", [RemovedName]),
                    loop(NewState)
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

remove_user_by_pid(Pid, State) ->
    remove_user_by_pid(Pid, State, []).
remove_user_by_pid(_, [], Acc) ->
    {not_found, lists:reverse(Acc)};
remove_user_by_pid(Pid, [U | Rest], Acc) ->
    case U#user.pid =:= Pid of
        true ->
            {U#user.name, lists:reverse(Acc) ++ Rest};
        false ->
            remove_user_by_pid(Pid, Rest, [U | Acc])
    end.