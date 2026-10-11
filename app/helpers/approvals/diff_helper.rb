# frozen_string_literal: true

# Approvals' comparison, word by word: one side of a changed text with what
# the other side doesn't have marked — removed words (<del>) on the live
# side, added ones (<ins>) on the proposed side — so a reviewer sees the
# change, not two copies of a paragraph to compare by eye.
module Approvals::DiffHelper
  # Past this many words a side, the whole text is marked instead: the
  # comparison is quadratic.
  WORD_LIMIT = 1_500

  # side: :live or :proposed.
  def approvals_word_diff(live, proposed, side:)
    before = approvals_words(live)
    after = approvals_words(proposed)
    mine, mark = side == :live ? [before, :del] : [after, :ins]
    return tag.public_send(mark, mine.join) if mine.any? && (before.size > WORD_LIMIT || after.size > WORD_LIMIT)

    common = approvals_common(before, after)
    kept = (side == :live ? common.map(&:first) : common.map(&:last)).to_set
    safe_join(mine.each_with_index.chunk_while { |(_, a), (_, b)| kept.include?(a) == kept.include?(b) }.map do |run|
      text = run.map(&:first).join
      kept.include?(run.first.last) || text.blank? ? text : tag.public_send(mark, text)
    end)
  end

  private

  # Each word, or run of punctuation, with the space after it: a run of
  # words marks as one, the spaces between them don't count as kept, and a
  # comma added after a word doesn't make the word look changed.
  def approvals_words(text) = text.to_s.scan(/\A\s+|[\p{L}\p{N}'’]+\s*|[^\p{L}\p{N}'’\s]+\s*/)

  # The longest run of words both sides share, as [live index, proposed index] pairs.
  def approvals_common(before, after)
    lengths = Array.new(before.size + 1) { Array.new(after.size + 1, 0) }
    before.each_index.reverse_each do |i|
      after.each_index.reverse_each do |j|
        lengths[i][j] = before[i] == after[j] ? lengths[i + 1][j + 1] + 1 : [lengths[i + 1][j], lengths[i][j + 1]].max
      end
    end
    pairs = []
    i = j = 0
    while i < before.size && j < after.size
      if before[i] == after[j]
        pairs << [i, j]
        i += 1
        j += 1
      elsif lengths[i + 1][j] >= lengths[i][j + 1]
        i += 1
      else
        j += 1
      end
    end
    pairs
  end
end
