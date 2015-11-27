require 'set'

module Racc
  # Helper to implement set-building algorithms, whereby each member which is
  # added to a set may result in still others being added, until the entire
  # set is found
  # Each member of the set (and the initial `worklist` if an explicit one is
  # given) will be yielded once; the block should either return `nil`, or an
  # `Enumerable` of more members
  def self.set_closure(seed, worklist = seed)
    worklist = worklist.to_a
    result   = Set.new(seed)

    until worklist.empty?
      if found = yield(worklist.shift, result)
        found.each do |member|
          worklist.push(member) if result.add?(member)
        end
      end
    end

    result
  end
end