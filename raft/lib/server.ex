
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)

defmodule Server do

# _________________________________________________________ Server.start()
def start(config, server_num) do
  config = config
    |> Configuration.node_info("Server", server_num)
    |> Debug.node_starting()

  receive do
  { :BIND, servers, databaseP } ->
    server = config |> State.initialise(server_num, servers, databaseP)

    # code to sleep and kill servers
    # if (config.crash_servers[server.server_num] != nil) do
    #   Process.send_after(server.selfP, {:KILL}, config.crash_servers[server.server_num])
    # end

    # if (config.sleep_servers[server.server_num] != nil) do
    #   Process.send_after(server.selfP, {:KILL}, config.sleep_servers[server.server_num])
    # end

    server
    |> Timer.restart_election_timer()
    |> Server.next()
  end # receive
end # start

# _________________________________________________________ next()
def next(server) do
  # invokes functions in AppendEntries, Vote, ServerLib etc
  #ensure every function in the receive statement returns a server map
  # so that the most up to date server map can be used when we call
  # next server again
  server = receive do
    { :ELECTION_TIMEOUT, election_status} ->
      if server.curr_election == election_status.election do
        ServerLib.start_election(server)
      else
        Debug.message(server, "-etim", "Old election timeout message", 2)
        server
      end

    { :APPEND_ENTRIES_REQUEST, term, prev_index, prev_term, entries, commit_index, from} ->
      Debug.message(server, "-areq", "Received append entries request with term #{server.curr_term}", 2)
      server |> AppendEntries.receive_req(term, prev_index, prev_term, entries, commit_index, from)

    { :DB_REPLY, _db_result } ->
      server

    { :APPEND_ENTRIES_REPLY, term, success, match_index, from} ->
      Debug.message(server, "-arep", "Received append entries reply", 2)
      server |> AppendEntries.receive_reply(term, success, match_index, from)

    { :APPEND_ENTRIES_TIMEOUT, follower_map} ->
      ServerLib.append_entries_timeout(server, follower_map)

    { :VOTE_REQUEST, term, from, id, lastLogTerm, lastLogIndex} ->
      Vote.receive_vote_req(server, term, from, id, lastLogTerm, lastLogIndex)

    { :VOTE_REPLY, term, vote, from} ->
      Vote.receive_vote_reply(server, term, vote, from)

    { :CLIENT_REQUEST, client_info} ->
      server |> ClientRequest.receive_client_request(client_info)

    {:SLEEP} ->
      Debug.message(server, "-sleep", "Is sleeping", 1)
      Process.sleep(2000)
      Debug.message(server, "-wake", "Is waking up", 1)
      server

    {:KILL} ->
      Debug.message(server, "-crash", "Is crashing", 1)
      Process.exit(server.selfP, :kill)
      server

  unexpected ->
      Helper.node_halt("***** Server: unexpected message #{inspect unexpected}")

  end # receive

  server |> Server.next()

end # next

end # Server
