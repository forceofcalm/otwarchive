# A class for keeping track of hits/IP addresses in redis. Writes the values in
# redis to the database when the HitCountUpdateJobs run.
class RedisHitCounter
  class << self
    include RedisScanning

    # Records a hit for the given IP address on the given work ID. If the IP
    # address hasn't visited the work within the current 24 hour block, we
    # increment the work's hit count. Otherwise, we do nothing.
    def add(work_id, ip_address)
      key = "visits:#{current_timestamp}"
      visit = "#{work_id}:#{ip_address}"

      # Add the (work ID, IP address) pair to the set for this date.
      added_visit = redis.sadd(key, visit)

      # If trying to add the (work ID, IP address) pair resulted in sadd
      # returning true, we know that the user hasn't visited this work
      # recently. So we increment the count of recent hits.
      redis.hincrby(:recent_counts, work_id, 1) if added_visit
    end

    # Go through the list of all keys starting with "visits:", compute the
    # timestamp from the key, and delete the sets associated with any
    # timestamps from before today.
    def remove_old_visits
      # NOTE: It's perfectly safe to convert the timestamp to an integer to be
      # able to compare with other timestamps, as we're doing here. However,
      # the integers shouldn't be used in any other way (e.g. subtraction,
      # addition, etc.) since they won't behave the way you'd expect dates to.
      last_timestamp = current_timestamp.to_i

      redis.scan_each(match: "visits:*", count: batch_size) do |key|
        _, timestamp = key.split(":")

        next unless timestamp.to_i < last_timestamp

        enqueue_remove_set(key)
      end
    end

    protected

    # Remove the set at the given key.
    #
    # Deletion technique adapted from:
    # https://www.redisgreen.net/blog/deleting-large-sets/
    def enqueue_remove_set(key)
      garbage_key = make_garbage_key

      # In order to make sure that we're not simultaneously adding to the set
      # and deleting it, we rename it.
      redis.rename(key, garbage_key)

      # We use async to perform the deletion because we don't want to lose
      # track of our garbage. If the key we're removing is in Resque, and the
      # job fails, it'll be retried until it succeeds.
      async(:remove_set, garbage_key)
    end

    # Scan through the given set and delete it batch-by-batch.
    def remove_set(key)
      scan_set_in_batches(redis, key, batch_size: batch_size) do |batch|
        redis.srem(key, batch)
      end
    end

    # Constructs an all-new key to use for deleting sets:
    def make_garbage_key
      "garbage:#{redis.incr('garbage:index')}"
    end

    public

    # The redis instance that we want to use for hit counts. We use a namespace
    # so that we can use simpler key names throughout this class.
    def redis
      @redis ||= Redis::Namespace.new(
        "hit_count",
        redis: REDIS_HITS
      )
    end

    # Take the current time (offset by the rollover hour) and convert it to a
    # date. We use this date as part of the key for storing which IP addresses
    # have viewed a work recently.
    def current_timestamp
      (Time.now.utc - rollover_hour.hours).to_date.strftime("%Y%m%d")
    end

    # The hour (in UTC time) that we want the hit counts to rollover at. If
    # someone views the work shortly before this hour and shortly after, it
    # counts as two hits.
    def rollover_hour
      ArchiveConfig.HIT_COUNT_ROLLOVER_HOUR
    end

    # The size of the batches to be retrieved from redis.
    def batch_size
      ArchiveConfig.HIT_COUNT_BATCH_SIZE
    end

    # Check whether the work should allow hits at the moment:
    def prevent_hits?(work)
      work.nil? ||
        work.in_unrevealed_collection ||
        work.hidden_by_admin ||
        !work.posted
    end

    ####################
    # DELAYED JOBS
    ####################

    # The default queue to use when enqueuing Resque jobs in this class:
    def queue
      :utilities
    end

    # This will be called by a worker when it's trying to perform a delayed
    # task. Calls the passed-in class method with the passed-in arguments.
    def perform(method, *args)
      send(method, *args)
    end

    # Queue up a method to be called later.
    def async(method, *args)
      Resque.enqueue(self, method, *args)
    end
  end
end
