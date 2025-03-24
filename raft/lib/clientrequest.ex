
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)

defmodule ClientRequest do

def receive_client_request(server, client_info) do

  cond do
    server.role == :LEADER and not duplicate(server, client_info)->

      entry = %{cmd: client_info.cmd, term: server.curr_term, cid: client_info.cid, clientP: client_info.clientP}
      server = server
        |> Log.append_entry(entry)
        |> State.applied(client_info.cid)
        |> State.match_index(server.selfP, Log.last_index(server))
        |> Monitor.send_msg({ :CLIENT_REQUEST, server.server_num })

      server |> AppendEntries.broadcast_append_entries(length(server.servers))

    server.role == :FOLLOWER or server.role == :CANDIDATE ->
      # Tell client who we think the leader is
      send client_info.clientP, {:CLIENT_REPLY, %{cid: client_info.cid, reply: :NOT_LEADER, leaderP: server.leaderP}}
      server
    true ->
      Debug.message(server, "-creq", "Disregarding request already seen", 2)
      server
    end
end

def duplicate(server, client_info) do
  MapSet.member?(server.applied, client_info.cid)
end

end # ClientRequest
