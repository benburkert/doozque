module Doozque
  # The stat subsystem. Used to keep track of integer counts.
  #
  #   Get a stat:  Stat[name]
  #   Incr a stat: Stat.incr(name)
  #   Decr a stat: Stat.decr(name)
  #   Kill a stat: Stat.clear(name)
  module Stat
    extend self
    extend Helpers

    # Returns the int value of a stat, given a string stat name.
    def get(stat)
      value = fraggle.get("/stat/#{stat}").value
      value.empty? ? 0 : value.to_i
    end

    # Alias of `get`
    def [](stat)
      get(stat)
    end

    # For a string stat name, increments the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # incremented by that amount.
    def incr(stat, by = 1)
      response = fraggle.get("/stat/#{stat}")
      if response.value.empty? && response.rev == 0
        fraggle.set("/stat/#{stat}", by.to_s)
      else
        fraggle.set("/stat/#{stat}", (response.value.to_i + by).to_s, response.rev)
      end
    end

    # Increments a stat by one.
    def <<(stat)
      incr stat
    end

    # For a string stat name, decrements the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # decremented by that amount.
    def decr(stat, by = 1)
      response = fraggle.get("/stat/#{stat}")
      if response.value.empty? && response.rev == 0
        fraggle.set("/stat/#{stat}", by.to_s)
      else
        fraggle.set("/stat/#{stat}", (response.value.to_i - by).to_s, response.rev)
      end
    end

    # Decrements a stat by one.
    def >>(stat)
      decr stat
    end

    # Removes a stat from Redis, effectively setting it to 0.
    def clear(stat)
      fraggle.del("/stat/#{stat}")
    end
  end
end
