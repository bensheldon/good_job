# frozen_string_literal: true

# Git worktree-aware naming so that multiple worktrees can run the test suite
# concurrently against the same PostgreSQL server without colliding.
module GitWorktree
  # Stored in ENV so that subprocesses (e.g. the generator specs' example app,
  # which lives outside the repository) resolve the same name.
  ENV_KEY = "GOOD_JOB_GIT_WORKTREE"

  def self.name
    ENV[ENV_KEY] ||= begin
      git_dir = IO.popen(["git", "-C", __dir__, "rev-parse", "--git-dir"], err: File::NULL, &:read).strip
      # Use the worktree directory name (set at creation) because branches may be renamed.
      git_dir.include?("/.git/worktrees/") ? File.basename(git_dir).gsub(/[^a-zA-Z0-9_]/, "_").squeeze("_").downcase : ""
    end
    ENV[ENV_KEY].empty? ? nil : ENV[ENV_KEY]
  end

  def self.db_suffix
    name ? "_#{name[0, 30]}" : ""
  end
end
