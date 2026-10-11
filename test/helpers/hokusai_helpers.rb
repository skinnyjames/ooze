
def get_blocks_by_type(block, type, results = [])
  if block.node.ast.type == type
    results << block

    return
  end

  block.children.each do |child|
    get_blocks_by_type(child, type, results)
  end

  results
end