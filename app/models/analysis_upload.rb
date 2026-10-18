# Where a raw upload waits on disk until AnalyzeHistoryJob has read it.
# Paths are built only from validated analysis UUIDs, never from user input.
# The worker must share this filesystem with the web process (true for the
# Solid Queue Puma plugin or bin/jobs on the same machine).
module AnalysisUpload
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  module_function

  def dir
    Pathname.new(ENV.fetch("ANALYSIS_UPLOAD_DIR", Rails.root.join("tmp/analysis_uploads").to_s))
  end

  def path_for(analysis_id)
    raise ArgumentError, "Invalid analysis id" unless UUID_FORMAT.match?(analysis_id.to_s)

    dir.join("#{analysis_id}.upload")
  end

  def store(analysis_id, source_path)
    FileUtils.mkdir_p(dir)
    FileUtils.cp(source_path, path_for(analysis_id))
  end

  def write(analysis_id, content)
    FileUtils.mkdir_p(dir)
    File.binwrite(path_for(analysis_id), content)
  end

  def read(analysis_id)
    File.read(path_for(analysis_id))
  end

  def exist?(analysis_id)
    File.exist?(path_for(analysis_id))
  end

  def delete(analysis_id)
    FileUtils.rm_f(path_for(analysis_id))
  end
end
