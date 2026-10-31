class CreateMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    # Single-use sign-in links. Only the SHA-256 digest of the token is stored.
    create_table :magic_link_tokens do |t|
      t.string   :email, null: false
      t.string   :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_index :magic_link_tokens, :token_digest, unique: true
    add_index :magic_link_tokens, :expires_at
  end
end
