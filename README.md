#### Description:
This script helps automate creating or updating user flairs on reddit. It will combine all images in a directory into one, generate the necessary css for the flairs to work and upload both to reddit. Then it will add new flair templates based on the name of those icons.

#### Usage:
* Install [Image Magick](http://www.imagemagick.org/script/binary-releases.php) and make sure you tick PerlMagick in the installer.
* Install dependencies listed below.
* Create user.txt and put your username on the first line and your password on the second one.
* Optionally create subreddit.txt and put your subreddit's name into it. Alternatively, you can pass an argument to the script with your subreddit.
* Create a directory named after your subreddit with all of the icons you want to create a sprite image from. Supported types are png, gif, ico.
* Create a comment section in your subreddit's stylesheet that looks like:
```
/* auto */
/* auto end */
```
* Run the script.

Note that the first time you run the script it is impossible to tell which flair templates exist and the script will complain about it. Subsequent runs will add flair template for any new files that are found.

#### Dependencies
* common::sense
* File::Slurp
* JSON::PP
* HTML::Entities

#### Other stuff
This script can also clear any existing flair templates and then readd all of them sorted by the flair template's name. This functionality is off by default as it will spam the moderation log.

Finally, the script will resize any icons larger than 16x16 by default and will not keep their aspect ratio. Disabling resizing completely will most likely produce invalid css code if the icons are of different dimensions.

You can change those two settings by editing the source code.