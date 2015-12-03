require 'set'

module Racc
  # Helper to implement set-building algorithms, whereby each member which is
  # added to a set may result in still others being added, until the entire
  # set is found
  # Each member of the set (and the initial `worklist` if an explicit one is
  # given) will be yielded once; the block should either return `nil`, or an
  # `Enumerable` of more members
  def self.set_closure(seed, worklist = seed)
    worklist = worklist.is_a?(Array) ? worklist.dup : worklist.to_a
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

  def self.to_sentence(words, conjunction = 'and')
    raise "Can't make a sentence out of zero words" if words.none?
    if words.one?
      words[0]
    elsif words.size == 2
      "#{words[0]} #{conjunction} #{words[1]}"
    else
      tail = words.pop
      "#{words.join(', ')} #{conjunction} #{tail}"
    end
  end
end