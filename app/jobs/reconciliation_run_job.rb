class ReconciliationRunJob < ApplicationJob
  queue_as :default

  # Lifecycle wrapper around Matchers::ExactMatcher. Owns the run's status
  # transitions, timing, stats persistence, and error capture. The matcher
  # itself is a pure service — it does not know about ReconciliationRun
  # status, started_at, or stats.
  #
  # On a retry, the previous run's error_message, completed_at, and stats
  # are cleared up-front. Note: this is a lifecycle reset only — it does
  # NOT roll back items already moved to "proposed" or "exception" by an
  # earlier successful matcher invocation. Those will simply be excluded
  # from the next run's candidate set.
  def perform(run_id)
    run = ReconciliationRun.find(run_id)
    run.update!(
      status: "running",
      started_at: Time.current,
      completed_at: nil,
      stats: {},
      error_message: nil
    )

    begin
      stats = Matchers::ExactMatcher.new(run).call
      run.update!(status: "complete", stats: stats, completed_at: Time.current)
    rescue => e
      run.update!(
        status: "failed",
        error_message: "#{e.class}: #{e.message}",
        completed_at: Time.current
      )
      raise
    end
  end
end
