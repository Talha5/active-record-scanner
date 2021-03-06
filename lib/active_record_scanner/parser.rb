require 'ripper'
require 'active_record_scanner/compactor'

class Parser
  def initialize(raw)
    @raw = raw
    @compactor = Compactor.new
  end

  def parse
    raw_tree = Ripper.sexp(@raw)
    return [] unless raw_tree # if the file isn't valid ruby, ignore it
    filtered_tree = filter(raw_tree)
    compact_tree = @compactor.deep_compact(filtered_tree) 
    return [] unless compact_tree # if the file has no queries or loops, ignore it
    normalise!(compact_tree)
  end

  private

  def is_block?(node)
    [:brace_block, :do_block].include?(node[0])
  end

  def is_query?(node)
    node[0] == :@ident && AR_METHODS.include?(node[1])
  end

  def is_loop?(node)
    node[0] == :@ident && LOOP_METHODS.include?(node[1])
  end

  # walk the tree and return a new tree with all nodes that aren't
  # loops, blocks or queries turned to `nil`
  def filter(new_tree = [], tree)
    tree.map.with_index do |node, i|
      if node.is_a?(Array) # we only care about non-leaf nodes
        if is_loop?(node)
          [ :loop, node, nil ]
        elsif is_block?(node)
          [ :block, node, filter(node)]
        elsif is_query?(node)
          # if the current node is a query, return it
          [:query, node] 
        elsif node
          filter(node)
        end
      end
    end
  end

  # walk the tree looking for blocks that immediately follow calls to
  # loop methods, and tag these blocks as blocks that are run inside loops
  def normalise!(tree)
    tree.each.with_index do |node, i|
      if node.is_a?(Array)
        if node.first == :loop && tree[i+1]
          key = tree[i+1][0]
          if key == :block
            tree[i+1][0] = :lblock
          elsif key == :query # wrap queries like `c.each(&:destroy)` 
            tree[i+1] = [:lblock, tree[i+1]]
          end
        end
        tree[i] = normalise!(node)
      end
    end
    tree
  end
end
