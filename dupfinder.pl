#!/usr/bin/perl -w

# dupfinder is a small tool to find duplicates 
# files in a filesystem.
# You can provide none, one or several
# directories where it will search (if no directory
# is provided, "." will be used)

# How it works: no much magic here. 
# First,
# it finds all the files in the specified directories, and
# create a hash (file_size_hash) of the form:
#         "filename" => file size 
# Then, the hash is inverted. Multiple files
# can have the same size (out first candidates of duplicates!).
# The inverted hash (size_files_hash) contains an array as value,
# with all the filenames of a given size:
#         file size => "filename"
#
# Second,
# another hash is created (file_md5_hash).
# This hash maps the filenames to is md5 hash value 
# Note that we only need to hash the files in the
# size_files_hash, since we are only interested
# in files with same length (take a look at
# sub process_checksums()). The current implementation
# will detect if we need to compute the md5 checksum
# for the current file by searching for its size
# in size_files_hash. This is "slow", since we have
# to look in a hash. We could improve speed
# by iterating directly in every value of size_files_hash.
# However, in practice, this seems not to be a bottleneck.
#
# Finally, as fdupes (http://premium.caribe.net/~adrian2/fdupes.html) does,
# we should do a bit-by-bit comparision of files with the same md5sum.
# This is NOT implemented now.

# TODO:
# * more options support. reference could be taken from fdupes
#   For instance: avoid certain patterns, scan certains pattern (v.g., .mp3),
#                 skip files with size less than/bigger than, hard links.
# * better warnings and messages
# 
# READ others TODO in the code

# Known BUGS:
# I can't find a way to prevent File::Find to try to change to a dir.
# This is a problem when the user has no permission to cd to that dir,
# since a message will be printed in STDERR. It would be
# nice to capture that error
#

# Changelog:
# Version 0.01. Initial release
# Maximiliano Combina -- maxicombina@gmail.com
# 29 January 2008

# COPYING:
# Distributed under GPLv2 of June 1991, which you can find at
# http://www.gnu.org/licenses/gpl-2.0.html

use strict;
use Data::Dumper;
use warnings;
use File::Find;
use Digest::MD5;
use File::stat;
use Cwd 'abs_path';
use Cwd 'getcwd';
# The idea with bundling is to support short and long options, such as
# --dumpinfo and -d. This seems not to work.
use Getopt::Long qw(:config bundling no_getopt_compat autoversion);


# Variables used to hold file information

# Hash to map filenames to byte size:
# "filename" => stat("filename")->size
my %file_size_hash = ();

# Inverse hash of %file_size_hash.
# It may contain duplicates values, thus the structure is:
# size => ["file1", "file2", ..., "fileN"]
my %size_files_hash = ();


# The hash to map filenames to md5 checksum.
# The structure is:
# "filename" => "md5 checksum"
my %file_md5_hash = ();

# Inverse of file_md5_hash
# Thus, the hash structure is:
# "md5 checksum" => ["filename1", "filename2", ..., "filenameN"]
my %md5_files_hash = ();


# Variables used to general work
my $md5 = Digest::MD5->new;
my $file_count = 0;
my $current_file_count = 0;

my @indicator = ('-', '\\', '|', '/');
my $progress_indicator = 0;

my $errors_processing_checksums = '';
my $errors_chdir = '';

# Command line variables
my $follow_symlinks = 0; # default: not to follow symlinks
my $dump_info = 0; # default: not to dump info
my $help_requested = 0;


# Everything ready. Let's start with main()
&main;


sub file_setup
{

    if ( -l $_ && ! $follow_symlinks ){
        #print "Discarding $_!!\n";
        return;
    }

    if (-f $_){
        print STDERR "\rBuilding file list $indicator[$progress_indicator]";

        $progress_indicator = ($progress_indicator + 1) % 4;

        $file_count++;

        $file_size_hash{$File::Find::name} = stat($_)->size;

    }
}

sub process_checksums
{
    my $filename = $_;
    
    if ( -l $_ && ! $follow_symlinks ){
        #printf "Skipping $_!!\n";
        return;
    }

    if ( -f $filename){
        $current_file_count++;
        my $percentage = int(100 * $current_file_count / $file_count);
        print STDERR "\rProgress [$current_file_count/$file_count] $percentage%";

        if (exists $size_files_hash{stat($filename)->size} ){

            if (open(FILE, "<", $filename)){
                #printf "\nProcessing file $filename\n"; 
                binmode(FILE);
                
                $file_md5_hash{$File::Find::name}=$md5->addfile(*FILE)->hexdigest;
                
                close(FILE);
            } else {
                # TODO: this code was reached because the size of this file is the same
                # than the code in some other(s) file(s)! Log  the other(s) file(s)!
                # NEWs: when a filane ends in space  (' '), open() also fails
                # It is weird to have such a filename, but... 
                $errors_processing_checksums .= "Warning! Could not open file '$File::Find::name': $!\n";
            }

        }
        
    }

}

sub dump_info
{
    if (! $dump_info ){
        return;
    }

    print "\nDUMPING file_size_hash\n";
    print Dumper \%file_size_hash;
    print "\n";
    
    print "\nDUMPING size_files_hash\n";
    print Dumper \%size_files_hash;
    print "\n";
    
    print "\nDUMPING file_md5_hash\n";
    print Dumper \%file_md5_hash;
    print "\n";

    print "\nDUMPING md5_files_hash\n";
    print Dumper \%md5_files_hash;
    print "\n";
    

    print "\nDUMPING more stats:\n";
    print "file_count = $file_count\n";
    print "current_file_count = $current_file_count\n";

}

sub print_help_and_exit
{
    print STDERR "Usage $0 [options] [dir1] [dir2] ...\n";
    print STDERR "\nOptions are:\n\n";
    print STDERR " -s --symlinks\tfollow symlinks. Default: disabled\n";
    print STDERR " -d --dumpinfo\tDump interesting variables after processing.\n";
    print STDERR "\t\tUseful for debugging only. Default: disabled\n";
    print STDERR " -? -h --help\tDisplay this help and exit\n";
    print STDERR "\n";
    exit;
}

sub main
{

    my $result = GetOptions ("symlinks|s" => \$follow_symlinks,
                             "dumpinfo|d" => \$dump_info,
                             "help|h|?" => \$help_requested);

    if ( $help_requested || ! $result ){
        &print_help_and_exit;
    }

    my @dirs = ();

    if (scalar(@ARGV) == 0){
        @dirs = ('.');
    } else {
        
        # We eliminate duplicate directories, by
        # normalizing all the paths in the command line (using Cwd::abs_path)
        # and inserting them in a hash.
        # The inspiring techinque is described in 'Perl Cookbook':
        # Recipe 4.6: Extracting Unique Elements from a list
        # available at http://www.unix.org.ua/orelly/perl/cookbook/ch04_07.htm

        my %seen = ();
        foreach my $item (@ARGV){
            
            if (! -e $item && ! -l $item){
                print STDERR "Warning! $item does not exist\n";
                next;
            } elsif ( ! -e $item && -l $item ){
                print STDERR "Warning! $item points nowhere\n";
                next;
            }

            if ( -d $item && -r $item && -x $item ){
                my $abs_path_to_item = abs_path($item);
                $seen{$abs_path_to_item}++;
            } else {

                if ( "" eq -d $item ){
                    print STDERR "Warning! '$item' does not seem a directory\n";
                } else {
                    print STDERR "Warning! directory '$item' can't be accessed\n";
                }

            }

        }

        @dirs = sort keys %seen;
        
        # If the user specified the current directory,
        # it is nice that he/she sees the duplicates
        # in the form "./path/to/dup".
        # Up to here, the directory was changed to absolute path,
        # and the user will see "/abs/path/to/here/path/to/dup".
        # we will revert this
        for (my $i = 0 ; $i < scalar (@dirs); $i++){
            if (getcwd() eq $dirs[$i]){
                $dirs[$i] = ".";
            }
        }
        
    }

#    print "follow_symlinks = $follow_symlinks\n";
#    print "dump_info = $dump_info\n";
#    print Dumper \@dirs;


    
    # First pass: detect total amount of files,
    # and detect those with same size
    foreach my $dir (@dirs){
        if ( -d $dir ){
            find ({wanted => \&file_setup, follow=>$follow_symlinks}, $dir);
        } else {
            print STDERR "$dir is not a directory! skipped\n";
        }
    }


    print STDERR " done!\n";

##    printf STDERR "\r%40s\r", " "; # Clean the console, stolen from fdupes.c version 1.40
#    print Dumper \%file_size_hash;



    for my $file (keys %file_size_hash){
        push(@{$size_files_hash{$file_size_hash{$file}}}, $file);
    }

    for my $size (keys %size_files_hash){
        my @possible_dups = @{$size_files_hash{$size}};

        if ( scalar (@possible_dups) == 1 ){
            delete $size_files_hash{$size};
        }
    }

    # Now %size_files_hash only contains sizes with 2 or
    # more matching files. It is enough to search here only.
#    print Dumper \%size_files_hash;
#    die "fake done\n";

    foreach my $dir (@dirs){
        if ( -d $dir ){
            find ({wanted => \&process_checksums, follow=>$follow_symlinks}, $dir);
        } else {
            print STDERR "$dir is not a directory! skipped\n";
        }
    }

    printf STDERR " done!\n";
##    printf STDERR "\r%40s\r", " "; # Clean the console, stolen from fdupes.c version 1.40
    
    printf STDERR $errors_processing_checksums."\n" if ($errors_processing_checksums);

    for my $file (keys %file_md5_hash){
        push(@{$md5_files_hash{$file_md5_hash{$file}}}, $file);
    }

    # We now iterate on the values. When we detect
    # that some value has more than 1 file name (i.e.,
    # the array has more than 1 element), we print
    # the file names: these are the duplicate files
    # TODO: this only relies on the md5 sum, we
    # should do a more exhaustive comparision, just
    # to be sure
    for my $duplicates (values %md5_files_hash){

        my $dup_size = scalar( @{$duplicates} );

        # file with duplicates hash
        if ( $dup_size > 1 ){

            my @dups_files; # will store all the filenames

            # insert filenames in the array
            for (my $i = 0; $i < $dup_size; $i++){
                push(@dups_files, $duplicates->[$i]);
            }

			# print the size of the group, in bytes. Any file in @duplicates will be useful
			print "size: ".$file_size_hash{$duplicates->[0]}."\n";
			
            # print sorted output
            for my $filename (sort @dups_files){
                print "$filename\n";
            }
            print "\n";
        }
    }


    &dump_info;
}
