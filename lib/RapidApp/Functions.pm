package RapidApp::Functions;
#use strict;
#use warnings;
require Exporter;
use Class::MOP::Class;

use Term::ANSIColor qw(:constants);
use Data::Dumper;
use RapidApp::RootModule;
use Clone qw(clone);
use JSON::PP qw(encode_json);
use Try::Tiny;
use Time::HiRes qw(gettimeofday tv_interval);


sub scream {
	local $_ = caller_data(3);
	scream_color(YELLOW . BOLD,@_);
}

sub scream_color {
	my $color = shift;
	local $_ = caller_data(3) unless (
		$_ eq 'no_caller_data' or (
			ref($_) eq 'ARRAY' and
			scalar(@$_) == 3 and
			ref($_->[0]) eq 'HASH' and 
			defined $_->[0]->{package}
		)
	);
	
	my $data = $_[0];
	$data = \@_ if (scalar(@_) > 1);
	$data = Dumper($data) if (ref $data);
	$data = '  ' . UNDERLINE . 'undef' unless (defined $data);

	my $pre = '';
	$pre = BOLD . ($_->[2]->{subroutine} ? $_->[2]->{subroutine} . '  ' : '') .
		'[line ' . $_->[1]->{line} . ']: ' . CLEAR . "\n" unless ($_ eq 'no_caller_data');
	
	print STDERR $pre . $color . $data . CLEAR . "\n";
}


# Takes a list and returns a HashRef. List can be a mixed Hash/List:
#(
#	item1 => { opt1 => 'foo' },
#	item2 => { key => 'data', foo => 'blah' },
#	'item3',
#	'item4',
#	item1 => { opt2 => 'foobar', opt3 => 'zippy do da' }
#)
# Bare items like item3 and item4 become {} in the returned hashref.
# Repeated items like item1 and merged
# also handles the first arg as a hashref or arrayref
sub get_mixed_hash_args {
	my @args = @_;
	return $args[0] if (ref($args[0]) eq 'HASH');
	@args = @{ $args[0] } if (ref($args[0]) eq 'ARRAY');
	
	my $hashref = {};
	my $last;
	foreach my $item (@args) {
		if (ref($item)) {
			die "Error in arguments" unless (ref($item) eq 'HASH' and defined $last and not ref($last));
			$hashref->{$last} = { %{$hashref->{$last}}, %$item };
			next;
		}
		$last = $item;
		$hashref->{$item} = {} unless (defined $hashref->{$item});
	}
	return $hashref;
}


# Takes a list and returns a Hash. Like get_mixed_hash_args, but
# list order is preserved
sub get_mixed_hash_args_ordered {
	my @args = @_;
	return $args[0] if (ref($args[0]) eq 'HASH');
	@args = @{ $args[0] } if (ref($args[0]) eq 'ARRAY');
	
	my $hashref = {};
	my @list = ();
	my $last;
	foreach my $item (@args) {
		if (ref($item)) {
			die "Error in arguments" unless (ref($item) eq 'HASH' and defined $last and not ref($last));
			$hashref->{$last} = { %{$hashref->{$last}}, %$item };
			push @list, $last, $hashref->{$last};
			next;
		}
		$hashref->{$item} = {} unless (defined $hashref->{$item});
		push @list,$item,$hashref->{$item} unless (ref $last);
		$last = $item;
	}
	return @list; # <-- preserve order
}


# returns \0 and \1 as 0 and 1, and returns 0 and 1 as 0 and 1
sub jstrue {
	my $v = shift;
	ref($v) eq 'SCALAR' and return $$v;
	return $v;
}


# The coderefs supplied here get called immediately after the
# _load_root_module method in RapidApp/RapidApp.pm
sub rapidapp_add_global_init_coderef {
	foreach my $ref (@_) {
		ref($ref) eq 'CODE' or die "rapidapp_add_global_init_coderef: argument is not a CodeRef: " . Dumper($ref);
		push @RapidApp::RootModule::GLOBAL_INIT_CODEREFS, $ref;
	}
}

# Returns an arrayref of hashes containing standard 'caller' function data
# with named properties:
sub caller_data {
	my $depth = shift || 1;
	
	my @list = ();
	for(my $i = 0; $i < $depth; $i++) {
		my $h = {};
		($h->{package}, $h->{filename}, $h->{line}, $h->{subroutine}, $h->{hasargs},
			$h->{wantarray}, $h->{evaltext}, $h->{is_require}, $h->{hints}, $h->{bitmask}) = caller($i);
		push @list,$h;
	}
	
	return \@list;
}

sub caller_data_brief {
	my $depth = shift || 1;
	my $list = caller_data($depth + 1);
	my $regex = shift;
	
	shift @$list;
	shift @$list;
	
	my @inc_parms = qw(subroutine line filename);
	
	my %inc = map { $_ => 1 } @inc_parms;
	
	my @new = ();
	my $seq = 0;
	foreach my $item (@$list) {
		if($regex and ! eval('$item->{subroutine} =~ /' . $regex . '/')) {
			$seq++;
			next;
		}
		push @new, ' . ' x $seq if ($seq);
		$seq = 0;
		push @new, { map { $_ => $item->{$_} } grep { $inc{$_} } keys %$item };
	}
	
	return \@new;
}

# Returns a list with duplicates removed. If passed a single arrayref, duplicates are
# removed from the arrayref in place, and the new list (contents) are returned.
sub uniq {
	my %seen = ();
	return grep { !$seen{$_}++ } @_ unless (@_ == 1 and ref($_[0]) eq 'ARRAY');
	return () unless (@{$_[0]} > 0);
	# we add the first element to the end of the arg list to prevetn deep recursion in the
	# case of nested single element arrayrefs
	@{$_[0]} = uniq(@{$_[0]},$_[0]->[0]);
	return @{$_[0]};
}

sub deref {
	my $ref = shift;
	my $type = ref $ref || return $ref,@_;
	die 'deref(): more than 1 argument not supported' if (@_ > 0);
	return $$ref if ($type eq 'SCALAR');
	return @$ref if ($type eq 'ARRAY');
	return %$ref if ($type eq 'HASH');
	die "deref(): invalid ref type '$type' - supported types: SCALAR, ARRAY and HASH";
}

# Generic function returns a short display string of a supplied value/values
# This is like a lite version of Dumper meant more for single values
# Accepts optional CodeRef as first argument for custom handling, for example,
# this would allow you to use Dumper instead for all ref values:
# print disp(sub{ ref $_ ? Dumper($_) : undef },$_) for (@vals);
sub disp {
	my $recurse = (caller(1))[3] eq __PACKAGE__ . '::disp' ? 1 : 0; #<-- true if called by ourself

	local $_{code} = $recurse ? $_{code} : undef;
	$_{code} = shift if(ref($_[0]) eq 'CODE' && @_>1 && $recurse == 0);
	if($_{code}) {
		local $_ = $_[0];
		my $cust = $_{code}->(@_);
		return $cust if (defined $cust);
	}
	
	return join(',',map {disp($_)} @_) if(@_>1);
	my $val = shift;
	return 'undef' unless (defined $val);
	if(ref $val) {
		return '[' . disp(@$val) . ']' if (ref($val) eq 'ARRAY');
		return '\\' . disp($$val) if (ref($val) eq 'SCALAR');
		return '{ ' . join(',',map { $_ . ' => ' . disp($val->{$_}) } keys %$val) . ' }' if (ref($val) eq 'HASH'); 
		return "$val" #<-- generic fall-back for other references
	}
	return "'" . $val . "'";
}

sub debug_around($@) {
	my ($pkg,$filename,$line) = caller;
	my $method = shift;
	my @methods = ( $method );
	@methods = @$method if (ref($method) eq 'ARRAY');
	
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	%opt = (
		pkg			=> $pkg,
		filename		=> $filename,
		line			=> $line,
		%opt
	);
	
	$pkg = $opt{pkg};
	
	foreach my $method (@methods) {
		my $around = func_debug_around($method, %opt);
		
		# It's a Moose class or otherwise already has an 'around' class method:
		if($pkg->can('around')) {
			$pkg->can('around')->($method => $around);
			next;
		}
		
		# The class doesn't have an around method, so we'll setup manually with Class::MOP:
		my $meta = Class::MOP::Class->initialize($pkg);
		$meta->add_around_method_modifier($method => $around)
		
	}
}

# Returns a coderef - designed to be a Moose around modifier - that will
# print useful debug info about the given function to which it is attached
sub func_debug_around {
	my $name = shift;
	my %opt = (ref($_[0]) eq 'HASH') ? %{ $_[0] } : @_; # <-- arg as hash or hashref
	
	%opt = (
		time				=> 1,
		verbose			=> 0,
		verbose_in		=> undef,
		verbose_out		=> undef,
		dump_maxdepth	=> 3,
		use_json			=> 0,
		stack				=> 0,
		instance			=> 0,
		color				=> GREEN,
		ret_color		=> RED.BOLD,
		arg_ignore		=> sub { 0 }, # <-- no debug output prited when this returns true
		return_ignore	=> sub { 0 },# <-- no debug output prited when this returns true
		around			=> sub { # around wrapper to allow the user to pass a different one to use:
									my $orig = shift;
									my $self = shift;
									return $self->$orig(@_);
								},
		%opt
	);
	
	$opt{verbose_in} = 1 if ($opt{verbose} and not defined $opt{verbose_in});
	$opt{verbose_out} = 1 if ($opt{verbose} and not defined $opt{verbose_out});
	
	$opt{dump_func} = sub {
		my $verbose = shift;
		return UNDERLINE . 'undef' . CLEAR unless (@_ > 0 and defined $_[0]);
		return  join(',',map { ref $_ ? "$_" : "'$_'" } @_) unless ($verbose);
		local $Data::Dumper::Maxdepth = $opt{dump_maxdepth};
		return Dumper(@_) unless ($opt{use_json});
		#return JSON::PP->new->allow_blessed->convert_blessed->allow_nonref->encode(\@_);
		return encode_json(\@_);
	} unless ($opt{dump_func});

	return sub {
		my $orig = shift;
		my $self = shift;
		my @args = @_;
		
		my $has_refs = 0;
		my @print_args = map { (ref($_) and ++$has_refs) ? "$_" : MAGENTA . "'$_'" . CLEAR } @args;
		
		my $in = '(' . join(',',@print_args) . '): ';
		
		my $class = $opt{pkg};
		if($opt{stack}) {
			my $stack = caller_data_brief($opt{stack} + 3);
			shift @$stack;
			shift @$stack;
			@$stack = reverse @$stack;
			my $i = $opt{stack};
			print STDERR "\n";
			foreach my $data (@$stack) {
				print STDERR '((stack ' . sprintf("%2s",$i--) . ')) ' . sprintf("%7s",'[' . $data->{line} . ']') . ' ' . 
					GREEN . $data->{subroutine} . CLEAR . "\n";
			}
			print STDERR '((stack  0)) ' .  sprintf("%7s",'[' . $opt{line} . ']') . ' ' .
				GREEN . $class . '::' . $name . "\n" . CLEAR;
			$class = "$self";
		}
		
		print STDERR '[' . $opt{line} . '] ' . CLEAR . $opt{color} . $class . CLEAR . '->' . 
				$opt{color} . BOLD . $name . CLEAR . $in;
		
		my $spaces = ' ' x (2 + length($opt{line}));
		my $in_func = sub {
			print STDERR "\n" . ON_WHITE.BOLD . BLUE . "$spaces Supplied arguments dump: " . 
				$opt{dump_func}->($opt{verbose_in},\@args) . CLEAR ."\n: " 
					if($has_refs && $opt{verbose_in});
		};
		
		# before timestamp:
		my $t0 = [gettimeofday];
		
		my $res;
		my @res;
		my @res_copy = ();
		if(wantarray) {
			try {
				@res = $opt{around}->($orig,$self,@args);
			} catch { $in_func->(); die (shift);};
			push @res_copy, @res;
		}
		else {
			try {
				$res = $opt{around}->($orig,$self,@args);
			} catch { $in_func->(); die (shift);};
			push @res_copy,$res;
		}
		
		# after timestamp, calculate elapsed (to the millisecond):
		my $elapsed = sprintf("%.3f", tv_interval($t0) );
		
		local $_ = $self;
		if(!$opt{arg_ignore}->(@args) && !$opt{return_ignore}->(@res_copy)) {
			
			$in_func->();
			
			my $result = $opt{ret_color} . $opt{dump_func}->($opt{verbose_out},@res_copy) . CLEAR;
			$result = "\n" . ON_WHITE.BOLD . "$spaces Returned: " . $result . "\n" if ($opt{verbose_out});
			$result .= ' ' . ON_WHITE.RED . '[' . $elapsed . 's]' . CLEAR if ($opt{time});
			print STDERR $result . "\n";
			
		}
		else {
			# 'arg_ignore' and/or 'return_ignore' returned true, so we're not
			# supposed to print anything... but since we already have, in case
			# the function would have barfed, we'll print a \r to move the cursor
			# to the begining of the line so it will get overwritten, which is
			# almost as good as if we had not printed anything in the first place...
			# (note if the function printed something too we're screwed)
			print STDERR "\r";
		}
		
		return wantarray ? @res : $res;
	};
}

# Lets you create a sub and set debug_around on it at the same time
sub debug_sub($&) {
	my ($pkg,$filename,$line) = caller;
	my ($name,$code) = @_; 
	
	my $meta = Class::MOP::Class->initialize($pkg);
	$meta->add_method($name,$code);
	
	return debug_around $name, pkg => $pkg, filename => $filename, line => $line;
}


# Automatically export all functions defined above:
BEGIN {
	our @ISA = qw(Exporter);
	our @EXPORT = Class::MOP::Class->initialize(__PACKAGE__)->get_method_list;
}

1;
