-module(chat_server).

-include("../include/chat.hrl").

-compile(export_all).

start() ->
    register(?MODULE, spawn(?MODULE, init, [])),
    io:format("Server starts and waits for messages.~n").

start_link() ->
    register(?MODULE, spawn_link(?MODULE, init, [])).

init() ->
    process_flag(trap_exit, true),
    loop([]).

loop(State) ->
    receive
        {Pid, Ref, {join, Name}} ->
            handle_join(Pid, Ref, Name, State);
        {Pid, Ref, leave} ->
            handle_leave(Pid, Ref, State);
        {Pid, Ref, {message, Text}} ->
            handle_message(Pid, Ref, Text, State);
        {'EXIT', Pid, Reason} ->
            handle_exit(Pid, Reason, State);
        shutdown ->
            exit(shutdown);
        Unknown ->
            io:format("Unknown message: ~p~n", [Unknown]),
            loop(State)
    end.

handle_join(Pid, Ref, Name, State) ->
    case username_exists(Name, State) of
        true ->
            Pid ! {Ref, {error, username_taken}},
            loop(State);
        false ->
            User = #user{name = Name, pid = Pid},
            link(Pid),
            notify_users({user_joined, Name}, State),
            Pid ! {Ref, {ok, joined}},
            loop([User | State])
    end.

handle_leave(Pid, Ref, State) ->
    case remove_user_by_pid(Pid, State) of
        {not_found, _} ->
            Pid ! {Ref, {error, not_found}},
            loop(State);
        {RemovedName, NewState} ->
            unlink(Pid),
            notify_users({user_left, RemovedName}, NewState),
            Pid ! {Ref, {ok, left}},
            io:format("User ~s left the room.~n", [RemovedName]),
            loop(NewState)
    end.

handle_message(Pid, Ref, Text, State) ->
    case find_user_by_pid(Pid, State) of
        not_found ->
            Pid ! {Ref, {error, not_registered}},
            loop(State);
        User ->
            Sender = User#user.name,
            broadcast_message(Pid, Sender, Text, State),
            Pid ! {Ref, ok},
            loop(State)
    end.

handle_exit(Pid, Reason, State) ->
    case remove_user_by_pid(Pid, State) of
        {not_found, _} ->
            io:format("Received EXIT from unknown pid ~p, reason: ~p~n", [Pid, Reason]),
            loop(State);
        {RemovedName, NewState} ->
            notify_users({user_disconnected, RemovedName}, NewState),
            io:format("User ~s crashes/exits.~n", [RemovedName]),
            loop(NewState)
    end.

username_exists(Name, State) ->
    lists:any(fun(U) -> U#user.name =:= Name end, State).

notify_users(Message, Users) ->
    lists:foreach(fun(U) ->
        U#user.pid ! Message
    end, Users).

broadcast_message(SenderPid, SenderName, Text, Users) ->
    lists:foreach(fun(U) ->
        case U#user.pid =/= SenderPid of
            true ->
                U#user.pid ! {message_from, SenderName, Text};
            false ->
                ok
        end
    end, Users).

terminate() ->
    ?MODULE ! shutdown.

join(Name) ->
    Ref = make_ref(),
    ?MODULE ! {self(), Ref, {join, Name}},
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

find_user_by_pid(_, []) ->
    not_found;
find_user_by_pid(Pid, [U | Rest]) ->
    case U#user.pid =:= Pid of
        true ->
            U;
        false ->
            find_user_by_pid(Pid, Rest)
    end.