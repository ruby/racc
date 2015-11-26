module Racc
  include Racc::Color

  class Warning < Struct.new(:type, :title, :details)
    def initialize(type, title, details = nil)
      super
    end

    def to_s
      msg = violet('Warning: ') << bright(title)
      msg << "\n" << details if details
      msg
    end

    # Would this warning contain more details in verbose mode?
    def verbose_details?
      type == :sr_conflict || type == :rr_conflict
    end
  end
end