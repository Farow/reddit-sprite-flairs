use common::sense;
use File::Find 'find';
use File::Slurp 'read_file';
use LWP::UserAgent;
use JSON::PP 'decode_json';
use File::Spec;
use HTML::Entities 'decode_entities';
use Storable qw|nstore retrieve|;

my $clear_templates  = 0;
my ($width, $height) = (16, 16); #flair width/height, will be resized if larger

# load info
my ($username, $password) = read_file 'user.txt', { 'chomp' => 1 };
my @data;
my $seen = retrieve 'flairs.dat' if -e 'flairs.dat';

my $subreddit;

if (@ARGV) {
	$subreddit = shift @ARGV;
}
else {
	$subreddit = read_file 'subreddit.txt';
}

# create ua with cookie support
my $ua = LWP::UserAgent->new(
	'agent'      => 'Flairbot 0.1 by Farow',
	'cookie_jar' => { 'file' => 'cookies.dat' },
);

say 'Logging in...';
my ($cookie, $modhash) = login($username, $password);

# look for flair icons in directory
find(\&icons, $subreddit);

if (!@data) {
	say 'No icons found!';
	exit 1;
}

# create sprite from icons, generate stylesheet and upload them
update_sprite();

# add new templates
update_templates();

sub login {
	my $response = $ua->post('https://pay.reddit.com/api/login', {
		'user'     => $username,
		'passwd'   => $password,
		'api_type' => 'json', # so that the server returns a cookie and a modhash
	});

	if (!$response->is_success) {
		say 'Error while logging in.';
		exit 1;
	}

	my $user = decode_json $response->decoded_content;
	my ($cookie, $modhash) = map { $user->{'json'}{'data'}{ $_ } } 'cookie', 'modhash';

	if (!length $modhash) {
		say 'Modhash not found!';
		exit 1;
	}

	return $cookie, $modhash;
}

sub icons {
	use Image::Magick;
	use POSIX 'ceil';

	if (/\.(?:ico|gif|png)$/) {
		my $filename = $_;
		my $base = $filename;
		$base =~ s/\..+//;
		push @data, {
			'filename' => File::Spec->rel2abs($_),
			'base'     => $base,
		};
	}
}

sub update_sprite {
	use Image::Magick;
	use POSIX 'ceil';

	my $editor = Image::Magick->new;
	my $i = 0;

	for (@data) {
		$i++;
		$editor->Read($_->{'filename'});

		# only keep the first frame
		if ($i < @$editor) {
			splice @$editor, $i;
		}

		#$_->{'width'}  = $editor->[$i - 1]->Get('width');
		#$_->{'height'} = $editor->[$i - 1]->Get('height');
	}


	# resize if needed
	for (@$editor) {
		if ($_->Get('width') > $width || $_->Get('height') > $height) {
			$_->AdaptiveResize('width' => $width, 'height' => $height, 'blur' => 0);
		}
	}

	# calculate the amount of columns the sprite will have
	my $columns = ceil sqrt @data;
	my $tile = $columns . 'x' . $columns;

	say 'Getting current stylesheet...';
	my $response = $ua->get("https://pay.reddit.com/r/$subreddit/about/stylesheet.json");

	if (!$response->is_success) {
		say 'Error while getting stylesheet...';
		exit 1;
	}

	my $style = decode_json $response->decoded_content;
	my $css   = decode_entities $style->{'data'}{'stylesheet'}; #server sends css with entities
	my $new   = generate_css($columns);

	if ($css =~ /\/\* auto \*\/.*?\/\* auto-end \*\//s) {
		$css =~ s/\/\* auto \*\/.*?\/\* auto-end \*\//\/* auto *\/\n$new\n\/* auto-end *\//s;
	}
	else {
		say 'Could not find /* auto */ section in the stylesheet!';
		exit 1;
	}

	say 'Creating sprite...';

	# add 1 pixel of space around each image
	my $output = $editor->Montage('background' => 'none', 'tile' => $tile, 'geometry' => '+1+1');
	$output->Write('sprite.png');

	say 'Updating sprite...';
	$response = $ua->post("https://pay.reddit.com/r/$subreddit/api/upload_sr_img", 
		'Content_Type' => 'form-data',
		'Content'      => [
			'header' => 0,
			'name'   => 'auto-sprite',
			'uh'     => $modhash,
			'file'   => [ 'sprite.png' ],
		],
	);

	if (!$response->is_success) {
		say 'Error while updating sprite!';
		exit 1;
	}

	say 'Updating stylesheet...';
	$response = $ua->post("https://pay.reddit.com/r/$subreddit/api/subreddit_stylesheet", {
		'op'                  => 'save',
		'stylesheet_contents' => $css,
		'uh'                  => $modhash,
		'api_type'            => 'json',
	});

	if (!$response->is_success) {
		say 'Error while updating stylesheet!';
		exit 1;
	}
}

sub update_templates {
	my @templates;

	if ($clear_templates) {
		say 'Clearing templates...';

		my $response = $ua->post("https://pay.reddit.com/r/$subreddit/api/clearflairtemplates.json", {
			'flair_type' => 'USER_FLAIR',
			'uh'         => $modhash,
		});

		if (!$response->is_success) {
			say 'Error while clearing templates!';
			exit 1;
		}

		# the new templates will be all the icons and anything in the templates file
		@templates = sort(read_file("$subreddit-templates.txt"), map { $_->{'base'} } @data);
	}
	else {
		# otherwise, just figure out which ones are the new ones
		# check for at least one entry
		if (ref $seen eq 'HASH' && exists $seen->{ $subreddit } && keys $seen->{ $subreddit }) {
			@templates = sort grep { !exists $seen->{ $subreddit }{ $_ } } map { $_->{'base'} } @data;
		}
	}

	if (@templates) {
		say 'Waiting 20s before continuing...';
		sleep 20;

		my $i = 0;
		for (@templates) {
			$i++;
			sleep 2;

			say sprintf 'Setting flair [%*d/%d] (%s)', length(scalar @templates), $i, scalar(@templates), $_;

			my $response = $ua->post("https://pay.reddit.com/r/$subreddit/api/flairtemplate.json", {
				'css_class'  => $_,
				'flair_type' => 'USER_FLAIR',
				'uh'         => $modhash,
			});

			if (!$response->is_success) {
				say 'Error while setting template!';
				say $response->status_line;
			}
		}
	}
	else {
		say 'No flair templates to update!';
	}

	# clear all entries and save the current ones
	delete $seen->{ $subreddit };

	for (map { $_->{'base'} } @data) {
		$seen->{ $subreddit }{ $_ } = 1;
	}

	nstore $seen, 'flairs.dat';
}

sub generate_css {
	my $columns = shift;
	my $css;

	my ($row, $col, $i) = (1, 1, 1);

	for (@data) {
		$css .= ".flair-$_->{'base'} {\n"
		      . "    background:transparent url(%%auto-sprite%%) no-repeat;\n"
		      . '    background-position: ' . -$col . 'px ' . -$row . "px;\n" 
		      . "}\n";

		$col += $width + 2; # 1px for each image

		if ($i > $columns - 1) {
			$row += $height + 2;
			$col = 1;
			$i   = 0;
		}
		$i++;
	}

	return $css;
}