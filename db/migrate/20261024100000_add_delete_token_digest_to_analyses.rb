class AddDeleteTokenDigestToAnalyses < ActiveRecord::Migration[8.1]
  def change
    # Nullable: analyses created before this column existed simply can't be
    # deleted by token (they expire after 7 days anyway).
    add_column :analyses, :delete_token_digest, :string
  end
end
