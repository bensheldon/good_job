# frozen_string_literal: true
class ThreadNameFormatter < ActiveSupport::Logger::SimpleFormatter
  def call(severity, timestamp, _progname, message)
    prefix = [emoji_hash(Thread.current.name), Thread.current.name, emoji_hash(Thread.current.name)].compact.join(" ")
    "#{ActiveSupport::LogSubscriber.new.send(:color, "[#{prefix}]", :magenta)} #{super}"
  end

  def emoji_hash(str)
    # Hash the input string using SHA256
    digest = Digest::SHA256.hexdigest(str || "")

    # Take the first few characters from the hash
    partial_digest = digest[0..4].to_i(16)

    # Define the ranges for the emojis
    ranges = [
      (0x1F345..0x1F35E), # Vegetables and some other food items
      (0x1F400..0x1F43E) # Animals
    ]

    # Combine all ranges into a single array of code points
    all_emojis = ranges.flat_map { |r| r.to_a }

    # Compute an index within the all_emojis array
    index = partial_digest % all_emojis.length

    # Convert the code point to a character (emoji)
    emoji = [all_emojis[index]].pack('U*')

    emoji
  end
end
