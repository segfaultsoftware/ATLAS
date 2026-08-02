class ManualPageExporter
  def self.call(page:, destination_path:)
    new(page:, destination_path:).call
  end

  def initialize(page:, destination_path:)
    @page = page
    @destination_path = Pathname(destination_path.to_s)
  end

  def call
    validate_destination_path!
    File.binwrite(destination_path, page.content.to_s.encode(Encoding::UTF_8))
    destination_path
  end

  private

  attr_reader :page, :destination_path

  def validate_destination_path!
    return unless destination_path.directory?

    raise ArgumentError, "destination file cannot be a directory: #{destination_path}"
  end
end
