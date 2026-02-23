# YT2NAS

1.) [NAS] install ffmpeg
```
sudo apt install ffmpeg
```

2.) [NAS] install yt-dlp
```
mkdir -p ~/.local/bin
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/.local/bin/yt-dlp
chmod a+rx ~/.local/bin/yt-dlp
~/.local/bin/yt-dlp --version

then adding PATH:

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.profile
source ~/.bashrc
```

3.) [NAS] configuring yt-dlp
```
3/1.) create folder for config:
mkdir -p ~/.config/yt-dlp
nano ~/.config/yt-dlp/config

3/2.) then paste this to the opened file:

# here you can specify where to save your downloads.
-P /mnt/NAS/Youtube

# specifying the file name; for other options, see yt-dlp (channel / date - title [id].ext)
-o "%(uploader)s/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s"

# it downloads in the best possible quality, but the maximum quality can be specified here; now it's 4k
-f bv*[height<=2160]+ba/b[height<=2160]
--merge-output-format mkv

# to avoid repeated downloads, an archive is necessary.
--download-archive /mnt/NAS/Youtube/.yt_archive.txt

# download settings
--retries 10
--fragment-retries 10
--concurrent-fragments 4

# error handling
--ignore-errors

# playlist enabling
--yes-playlist

3/3.) create the download folder:

mkdir -p /mnt/NAS/Youtube

3/4.) if you use another user to access your NAS, add them so that they can also manage this folder:

sudo chown -R your_username:your_username /mnt/NAS/Youtube
sudo chmod -R u+rwX /mnt/NAS/Youtube
```

4.) [NAS] install deno:
```
curl -fsSL https://deno.land/install.sh | sh
echo 'export DENO_INSTALL="$HOME/.deno"' >> ~/.bashrc
echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
deno --version
```

5.) [NAS] make the queue:
```
mkdir -p /mnt/NAS/Youtube/.queue
touch /mnt/NAS/Youtube/.queue/queue.txt
touch /mnt/NAS/Youtube/.queue/archive.txt
touch /mnt/NAS/Youtube/.queue/yt-dlp.log


```
