class Shelly::Client
  def add_ssh_key(ssh_key)
    post("/ssh_keys", :ssh_key => ssh_key)
  end

  def delete_ssh_key(ssh_key)
    delete("/ssh_keys", :ssh_key => ssh_key)
  end
end
