# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)
defmodule ServerLib do

  def start_election(server) do
    if (server.role in [:CANDIDATE, :FOLLOWER]) do
      Debug.message(server, "-etim", "Starting election with new term #{server.curr_term + 1}", 1)
      server
        |> State.new_voted_by() # Added this as makes sense but not in pseudo code
        |> Timer.restart_election_timer()
        |> State.inc_term()
        |> State.role(:CANDIDATE)
        |> State.voted_for(server.server_num)
        |> State.add_to_voted_by(server.server_num)
        |> trigger_timeout(0)
    else
      server
    end
  end # start_election

  #triggering append entries timeout to send vote requests
  defp trigger_timeout(server, server_index) do
    if length(server.servers) == server_index do
      server
    else
      server_receiver = Enum.at(server.servers, server_index)
      server = if (server_receiver != server.selfP) do
        server = server |> Timer.cancel_append_entries_timer(server_receiver)
        send server.selfP, {:APPEND_ENTRIES_TIMEOUT, %{term: server.curr_term, followerP: server_receiver}}
        server
      else
        server
      end
      server |> trigger_timeout(server_index + 1)
    end
  end

  def append_entries_timeout(server, map) do
    case server.role do
      :CANDIDATE ->
        Debug.message(server, "-atim", {"Received append entries timeout, sending vote request to", map.followerP}, 2)
        server = server |> Timer.restart_append_entries_timer(map.followerP)
        last_log_index = Log.last_index(server)
        last_log_term = server |> Log.term_at(last_log_index)
        server |> Vote.request_vote(map.term, map.followerP, last_log_term, last_log_index)
      :LEADER ->
        Debug.message(server, "-atim", {"Sending append entries to follower", map.followerP}, 2)
        server |> send_append_entries(map.followerP)
      :FOLLOWER -> server
    end
  end

  def send_append_entries(server, server_receiver) do
    server = server |> Timer.restart_append_entries_timer(server_receiver)

    # removed the log length from here
    last_log_index = server.next_index[server_receiver] - 1

    # leaders term, prev index, prev term from leader, entries to update, commit index, from
    send server_receiver, { :APPEND_ENTRIES_REQUEST, server.curr_term, last_log_index, Log.term_at(server, last_log_index),
                            Log.get_entries_from(server, last_log_index + 1), server.commit_index, server.selfP}
    server
  end

  def stepdown(server, term) do
    server
      |> State.curr_term(term)
      |> State.role(:FOLLOWER)
      |> State.voted_for(nil)
      |> Timer.restart_election_timer()
  end

# Library of functions called by other server-side modules

# -- omitted

end # ServerLib
