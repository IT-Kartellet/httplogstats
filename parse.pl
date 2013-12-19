#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use Storable qw(nstore retrieve);
use Time::HiRes qw(gettimeofday tv_interval);

my $fields_re = qr/
^
(?<date>\d{4}-\d{2}-\d{2})\s
(?<time>\d{2}:\d{2}:\d{2})\s
(?<serverip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s
(?<method>POST|GET|HEAD|OPTIONS|INDEX|PROPFIND|MKCOL|LOCK|UNLOCK|TRACK|PUT|SEARCH|TRACE)\s
(?<url>[^\s]+)\s
(?<query>[^\s]+)\s
(?<port>\d+)\s
(?<username>[^\s]+)\s
(?<clientip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s
(?<useragent>[^\s]+)\s
(?<statuscode>\d+)\s
(?<substatuscode>\d+)\s
(?<win32status>\d+)\s
(?<timetaken>\d+)
(?:\r\n)?$
/ix;

my $init_record = { 
    sum => 0, max => 0, min => 2147483647, cnt => 0, 
    frequency => { (map { $_ => 0 } 500, 1_000, 3_000, 5_000, 10_000, 30_000, 60_000, 120_000, 240_000, 600_000, 3600_000) },
}; 
my @frequencys = sort { $a <=> $b } keys %{$init_record->{frequency}}; 

my $corenum = 4;

my $path = shift or die './parse.pl <directory>';
my %files = getfiles(qr/\.log$/, $path);

# Devide the files into different jobs base on size
my @jobs = map { [] } 1..$corenum;
my @sums = (0) x $corenum;
my $sum = 0;
print Dumper(\@jobs);
foreach my $file (sort keys %files) {
    #next if $file !~ /u_ex130706\.log$/;
    my $i = 0;
    my $min_sum = $sums[$i];
    for(my $j=0; $j < $corenum; $j++) {
        if($min_sum >= $sums[$j]) {
            $i = $j;
        }
    }
    $sums[$i] += $files{$file}[7];
    $sum += $files{$file}[7];
    push(@{$jobs[$i]}, $file);
}
print "Starting to parse ".($sum / 1024 / 1024)."MB of logs\n";

#print Dumper(\@sums);
print Dumper(\@jobs);

my %pids;
for(my $i = 0; $i < $corenum; $i++) {
    next if @{$jobs[$i]} == 0; 

    my $pid = fork;
    if($pid == 0) {
        my %stats;
        my $totalcount = 0;
        my $filecount = 0;
        foreach my $file (@{$jobs[$i]}) {
            my $t0 = [gettimeofday];
            my $count = 0;
            open my $fh, "<", $file or die "Could not open file $file: $!";
            while(<$fh>) {
                if(/^#.*/) {
                    next;
                } elsif(/$fields_re/) {
                    my $key = "$+{date}:$+{method}:".lc($+{url});
                    #next if $+{url} ne '/default.aspx';
                    $count++;
                    $totalcount++;

                    # Get current url obj or create new
                    my $item = !exists $stats{$key} ? ($stats{$key} = { %$init_record, frequency => { %{$init_record->{frequency}} } }) : $stats{$key};

                    # Skip urls with error code 500, 404, etc.
                    if($+{statuscode} == 500) { push(@{$item->{"error500"}}, "$file:$."); next; }
                    if($+{statuscode} > 204) { $item->{"code$+{statuscode}"}++; next; }

                    #print $_ if($+{timetaken} < 30_000);

                    # Save stats on how long it takes
                    $item->{sum} += $+{timetaken};
                    $item->{max} = $+{timetaken} if $item->{max} < $+{timetaken}; 
                    $item->{min} = $+{timetaken} if $item->{min} > $+{timetaken}; 
                    $item->{cnt}++;

                    # Find frequency of wait times
                    foreach my $frequency (@frequencys) {
                        if($frequency >= $+{timetaken}) {
                            $item->{frequency}{$frequency}++;
                            last;
                        }
                    }

                } else {
                    print "Could not parse line: ".$_;
                }
            }
            close $fh;
            my $elapsed = tv_interval ($t0);
            printf STDERR "%d : %s : %d : %.2f/s : %d\n", $i, $file, $count, ($count / $elapsed), (@{$jobs[$i]} - ++$filecount);
        }
        nstore(\%stats, "results$i.dat");
        exit 0;
    }
    print "Starting job $pid\n";
    $pids{$pid} = $i;
}

# Get the exit code
my %stats;
while((my $pid = waitpid(-1, 0)) != -1) {
    my $exit_code = $? >> 8;
    print "Job $pid stoped: $exit_code, processing results\n";

    my $hash = retrieve("./results$pids{$pid}.dat");
    unlink "./results$pids{$pid}.dat"; 
    foreach my $url (keys %{$hash}) {
        # Create an inital entry if non exists
        $stats{$url} = { %$init_record, frequency => { %{$init_record->{frequency}} } } if !exists $stats{$url};

        $stats{$url}{sum} += $hash->{$url}{sum}; 
        $stats{$url}{cnt} += $hash->{$url}{cnt}; 

        foreach my $code (grep { /^code/ } keys %{$hash->{$url}}) {
            $stats{$url}{$code} += $hash->{$url}{$code};
        }

        foreach my $frequency (@frequencys) {
            $stats{$url}{frequency}{$frequency} += $hash->{$url}{frequency}{$frequency};
        }

        $stats{$url}{max} = $hash->{$url}{max} if $stats{$url}{max} < $hash->{$url}{max}; 
        $stats{$url}{min} = $hash->{$url}{min} if $stats{$url}{min} > $hash->{$url}{min}; 

        push(@{$stats{$url}{error500}}, @{$hash->{$url}{error500}}) if exists $hash->{$url}{error500}; 
    }
    #print Dumper(\%stats);
}

$path =~ qr|([^/]+)$|;
nstore(\%stats, "$1.dat");

sub getfiles {
    my ($filter, @paths) = @_;
    my %files;

    while (my $path = shift @paths) {
        opendir(my $dir, $path);
        while(my $file = readdir $dir) {
            next if($file eq '.' or $file eq '..');

            if(-d "$path/$file") {
                push @paths, "$path/$file";
            } elsif(-f "$path/$file" and "$path/$file" =~ $filter) {
                $files{"$path/$file"} = [stat("$path/$file")];
            }
        }
        closedir($dir);
    }
    return %files;
}

