
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)

defmodule Log do

# implemented as a Map indexed from 1.

def new()                     do Map.new() end                      # used when process state is initialised
def new(server)               do Map.put(server, :log, Map.new) end # not currently used
def new(server, log)          do Map.put(server, :log, log) end     # only used below

def last_index(server)        do map_size(server.log) end
def entry_at(server, index)   do server.log[index] end
def request_at(server, index) do server.log[index].request end
def term_at(_server, 0)       do 0 end
def term_at(server, index)    do server.log[index].term end
def last_term(server)         do Log.term_at(server, Log.last_index(server)) end

def get_entries(server, range) do                 # e.g return server.log[3..5]
  Map.take(server.log, Enum.to_list(range))
  # equivalent to
  #   for k <- range.first .. range.last // 1, into: Map.new do {k, Log.entry_at(server, k)} end
end

def get_entries_from(server, from) do               # e.g return server.log[3..]
  for k <- from .. Log.last_index(server) // 1, into: Map.new do
    {k, Log.entry_at(server, k)}
  end
end

def get_cids_from(server, from) do               # e.g return server.log[3..]
  for k <- from .. Log.last_index(server) // 1, into: MapSet.new do
    Log.entry_at(server, k).cid
  end
end

def append_entry(server, entry) do
  Log.new(server, Map.put(server.log, Log.last_index(server)+1, entry))
end

def merge_entries(server, entries) do               # entries should be disjoint
  Log.new(server, Map.merge(server.log, entries))
end

def delete_entries(server, range) do                 # e.g. delete server.log[3..5] keep rest
  Log.new(server, Map.drop(server.log, Enum.to_list(range)))
end

def delete_entries_from(server, from) do             # delete server.log[from..last] keep rest
  Log.delete_entries(server, from .. Log.last_index(server) // 1 )
end

def store_entries(server, prev_index, entries, commitIndex) do
  last_index = prev_index + map_size(entries)

  cids_to_remove = for k <- prev_index + 1 .. Log.last_index(server) // 1, into: MapSet.new do
    Log.entry_at(server, k).cid
  end
  cids_to_add = for k <- prev_index + 1 .. last_index // 1, into: MapSet.new do
    entries[k].cid
  end
  cids_to_keep = MapSet.difference(server.applied, cids_to_remove)
  cids_new = MapSet.union(cids_to_keep, cids_to_add)

  server = server
    |> Map.put(:applied, cids_new)
    |> Log.delete_entries_from(prev_index + 1)
    |> Log.merge_entries(entries)
    |> State.commit_index(min(commitIndex, last_index))

  {server, last_index}
end

end # Log
