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
        Message when is_tuple(Message) ->
            handle_message(Message, State);
        shutdown ->
            notify_users(server_down, State),
            io:format("Server shuts down.~n"),
            exit(shutdown);
        Unknown ->
            io:format("Unknown message: ~p~n", [Unknown]),
            loop(State)
    end.

% Handlers

handle_message({Pid, Ref, {join, Name}}, State) ->
    case username_exists(Name, State) of
        true ->
            Pid ! {Ref, {error, username_taken}},
            loop(State);
        false ->
            MonitorRef = erlang:monitor(process, Pid),
            User = #user{name = Name, pid = Pid, monitor_ref = MonitorRef},
            notify_users({user_joined, Name}, State),
            Pid ! {Ref, {ok, joined}},
            loop([User | State])
    end;

handle_message({Pid, Ref, leave}, State) ->
    case remove_user_by_pid(Pid, State) of
        {not_found, _} ->
            Pid ! {Ref, {error, not_found}},
            loop(State);
        {RemovedUser, NewState} ->
            erlang:demonitor(RemovedUser#user.monitor_ref, [flush]),
            notify_users({user_left, RemovedUser#user.name}, NewState),
            Pid ! {Ref, {ok, left}},
            io:format("User ~s left the room.~n", [RemovedUser#user.name]),
            loop(NewState)
    end;

handle_message({Pid, Ref, {message, Text}}, State) ->
    case find_user_by_pid(Pid, State) of
        not_found ->
            Pid ! {Ref, {error, not_registered}},
            loop(State);
        User ->
            Sender = User#user.name,
            broadcast_message(Pid, Sender, Text, State),
            Pid ! {Ref, ok},
            loop(State)
    end;

handle_message({'DOWN', _MonitorRef, process, Pid, Reason}, State) ->
    case remove_user_by_pid(Pid, State) of
        {not_found, _} ->
            io:format("Received DOWN from unknown pid ~p, reason: ~p~n", [Pid, Reason]),
            loop(State);
        {RemovedUser, NewState} ->
            notify_users({user_disconnected, RemovedUser#user.name}, NewState),
            io:format("User ~s disconnected. Reason: ~p~n", [RemovedUser#user.name, Reason]),
            loop(NewState)
    end;



handle_message(Other, State) ->
    io:format("Debug: unknown tuple message ~p~n", [Other]),
    loop(State).

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

remove_user_by_pid(Pid, State) ->
    remove_user_by_pid(Pid, State, []).
remove_user_by_pid(_, [], Acc) ->
    {not_found, lists:reverse(Acc)};
remove_user_by_pid(Pid, [U | Rest], Acc) ->
    case U#user.pid =:= Pid of
        true ->
            {U, lists:reverse(Acc) ++ Rest};
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