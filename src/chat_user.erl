-module(chat_user).
-include("../include/chat.hrl").
-compile(export_all).

start(Name) ->
    spawn(?MODULE, init, [Name]).

init(Name) ->
    case request_join(Name) of
        {ok, joined, ServerMonitorRef} ->
            io:format("User ~s joins.~n", [Name]),
            loop(Name, ServerMonitorRef);
        {error, username_taken} ->
            io:format("Username ~s is already taken.~n", [Name]);
        {error, server_not_found} ->
            io:format("Server is not running. User ~s cannot join.~n", [Name]);
        {error, timeout} ->
            io:format("Join timed out for ~s.~n", [Name]);
        {error, Reason} ->
            io:format("Join failed for ~s. Reason: ~p~n", [Name, Reason])
    end.

loop(Name, ServerMonitorRef) ->
    receive
        {user_joined, OtherName} ->
            io:format("Server tells User ~s: User ~s has joined the room.~n", [Name, OtherName]),
            loop(Name, ServerMonitorRef);
        {user_disconnected, OtherName} ->
            io:format("Server tells User ~s: User ~s has disconnected.~n", [Name, OtherName]),
            loop(Name, ServerMonitorRef);
        leave ->
            request_leave(Name, ServerMonitorRef);
        {user_left, OtherName} ->
            io:format("Server tells User ~s: User ~s has left the room.~n", [Name, OtherName]),
            loop(Name, ServerMonitorRef);
        {message_from, Sender, Text} ->
            io:format("User ~s receives from ~s: ~s~n", [Name, Sender, Text]),
            loop(Name, ServerMonitorRef);
        {send_message, Text} ->
            request_send_message(Name, Text, ServerMonitorRef);
        server_down ->
            io:format("Server is disconnected. User ~s shuts down.~n", [Name]),
            exit(normal);
        {'DOWN', ServerMonitorRef, process, _Pid, Reason} ->
            io:format("Server went down. Reason: ~p. User ~s shuts down.~n", [Reason, Name]),
            exit(normal);
        Other ->
            io:format("User ~s received unknown message: ~p~n", [Name, Other]),
            loop(Name, ServerMonitorRef)
    end.

request_join(Name) ->
    case whereis(chat_server) of
        undefined ->
            {error, server_not_found};
        ServerPid ->
            ServerMonitorRef = erlang:monitor(process, ServerPid),
            Ref = make_ref(),
            ServerPid ! {self(), Ref, {join, Name}},
            receive
                {Ref, {ok, joined}} ->
                    {ok, joined, ServerMonitorRef};
                {Ref, {error, username_taken}} ->
                    erlang:demonitor(ServerMonitorRef, [flush]),
                    {error, username_taken};
                {'DOWN', ServerMonitorRef, process, _Pid, Reason} ->
                    {error, Reason}
            after 5000 ->
                erlang:demonitor(ServerMonitorRef, [flush]),
                {error, timeout}
            end
    end.

leave(UserPid) ->
    UserPid ! leave.

request_leave(Name, ServerMonitorRef) ->
    case whereis(chat_server) of
        undefined ->
            io:format("Server is not running. User ~s cannot leave cleanly.~n", [Name]),
            erlang:demonitor(ServerMonitorRef, [flush]),
            exit(normal);
        ServerPid ->
            Ref = make_ref(),
            ServerPid ! {self(), Ref, leave},
            receive
                {Ref, {ok, left}} ->
                    erlang:demonitor(ServerMonitorRef, [flush]),
                    exit(normal);
                {Ref, {error, not_found}} ->
                    io:format("User ~s could not leave the room.~n", [Name]),
                    loop(Name, ServerMonitorRef);
                {'DOWN', ServerMonitorRef, process, _Pid, Reason} ->
                    io:format("Server went down during leave for ~s. Reason: ~p~n", [Name, Reason]),
                    exit(normal)
            after 5000 ->
                io:format("Leave timed out for ~s.~n", [Name]),
                loop(Name, ServerMonitorRef)
            end
    end.

request_send_message(Name, Text, ServerMonitorRef) ->
    case whereis(chat_server) of
        undefined ->
            io:format("Server is not running. User ~s cannot send message.~n", [Name]),
            loop(Name, ServerMonitorRef);
        ServerPid ->
            Ref = make_ref(),
            ServerPid ! {self(), Ref, {message, Text}},
            receive
                {Ref, ok} ->
                    loop(Name, ServerMonitorRef);
                {Ref, {error, not_registered}} ->
                    io:format("User ~s is not registered.~n", [Name]),
                    loop(Name, ServerMonitorRef);
                {'DOWN', ServerMonitorRef, process, _Pid, Reason} ->
                    io:format("Server went down while sending message for ~s. Reason: ~p~n", [Name, Reason]),
                    exit(normal)
            after 5000 ->
                io:format("Message send timed out for ~s.~n", [Name]),
                loop(Name, ServerMonitorRef)
            end
    end.

send(UserPid, Text) ->
    UserPid ! {send_message, Text},
    ok.