class ManualPageImporter
  def self.call(page:, source_path:)
    new(page:, source_path:).call
  end

  def initialize(page:, source_path:)
    @page = page
    @source_path = Pathname(source_path.to_s)
  end

  def call
    validate_source_path!

    content = File.binread(source_path).force_encoding(Encoding::UTF_8)
    raise ArgumentError, "source file must contain valid UTF-8 text" unless content.valid_encoding?

    page.update!(content:)
    page
  end

  private

  attr_reader :page, :source_path

  def validate_source_path!
    return if source_path.file?

    raise ArgumentError, "source file does not exist: #{source_path}"
  end
end
