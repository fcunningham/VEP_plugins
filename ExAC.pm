=head1 LICENSE

 Copyright (c) 1999-2015 The European Bioinformatics Institute and
 Genome Research Limited.  All rights reserved.                                                                      

 This software is distributed under a modified Apache license.                                                       
 For license details, please see

   http://www.ensembl.org/info/about/code_licence.html                                                               

=head1 CONTACT                                                                                                       

 Will McLaren <wm2@ebi.ac.uk>
    
=cut

=head1 NAME

 ExAC

=head1 SYNOPSIS

 mv ExAC.pm ~/.vep/Plugins
 perl variant_effect_predictor.pl -i variations.vcf --plugin ExAC,/path/to/ExAC/ExAC.r0.3.sites.vep.vcf.gz

=head1 DESCRIPTION

 A VEP plugin that retrieves ExAC allele frequencies.
 
 Visit ftp://ftp.broadinstitute.org/pub/ExAC_release/current to download the latest ExAC VCF.
 
 The tabix utility must be installed in your path to use this plugin.
 
=cut

package ExAC;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Sequence qw(reverse_comp);
use Bio::EnsEMBL::Variation::Utils::VEP qw(parse_line);

use Bio::EnsEMBL::Variation::Utils::BaseVepPlugin;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepPlugin);

sub new {
  my $class = shift;
  
  my $self = $class->SUPER::new(@_);
  
  # test tabix
  die "ERROR: tabix does not seem to be in your path\n" unless `which tabix 2>&1` =~ /tabix$/;
  
  # get ExAC file
  my $file = $self->params->[0];
  
  # remote files?
  if($file =~ /tp\:\/\//) {
    my $remote_test = `tabix -f $file 1:1-1 2>&1`;
    if($remote_test && $remote_test !~ /get_local_version/) {
      die "$remote_test\nERROR: Could not find file or index file for remote annotation file $file\n";
    }
  }

  # check files exist
  else {
    die "ERROR: ExAC file $file not found; you can download it from ftp://ftp.broadinstitute.org/pub/ExAC_release/current\n" unless -e $file;
    die "ERROR: Tabix index file $file\.tbi not found - perhaps you need to create it first?\n" unless -e $file.'.tbi';
  }
  
  $self->{file} = $file;
  
  return $self;
}

sub feature_types {
  return ['Feature','Intergenic'];
}

sub get_header_info {
  my $self = shift;
  
  if(!exists($self->{header_info})) {
    open IN, "tabix -f -h ".$self->{file}." 1:1-1 |";
    
    my %headers = ();
    my @lines = <IN>;
    
    while(my $line = shift @lines) {
      if($line =~ /ID\=AC(\_[A-Z]+)?\,.*\"(.+)\"/) {
        my ($pop, $desc) = ($1, $2);
        
        $desc =~ s/Counts?/frequency/i;
        $pop ||= '';
        
        my $field_name = 'ExAC'.$pop.'_AF';
        $headers{$field_name} = 'ExAC '.$desc;
        
        # store this header on self
        push @{$self->{headers}}, 'AC'.$pop;
      }
    }
    
    close IN;
    
    die "ERROR: No valid headers found in ExAC VCF file\n" unless scalar keys %headers;
    
    $self->{header_info} = \%headers;
  }
  
  return $self->{header_info};
}

sub run {
  my ($self, $tva) = @_;
  
  my $vf = $tva->variation_feature;
  
  # get allele, reverse comp if needed
  my $allele;
  
  $allele = $tva->variation_feature_seq;
  reverse_comp(\$allele) if $vf->{strand} < 0;
  
  # adjust coords to account for VCF-like storage of indels
  my ($s, $e) = ($vf->{start} - 1, $vf->{end} + 1);
  
  my $pos_string = sprintf("%s:%i-%i", $vf->{chr}, $s, $e);
  
  # clear cache if it looks like the coords are the same
  # but allele type is different
  delete $self->{cache} if
    defined($self->{cache}->{$pos_string}) &&
    scalar keys %{$self->{cache}->{$pos_string}} &&
    !defined($self->{cache}->{$pos_string}->{$allele});
  
  my $data = {};
  
  # cached?
  if(defined($self->{cache}) && defined($self->{cache}->{$pos_string})) {
    $data = $self->{cache}->{$pos_string};
  }
  
  # read from file
  else {
    open TABIX, sprintf("tabix -f %s %s |", $self->{file}, $pos_string);
    
    while(<TABIX>) {
      chomp;
      s/\r$//g;
      
      # parse VCF line into a VariationFeature object
      my ($vcf_vf) = @{parse_line({format => 'vcf'}, $_)};
      
      # check parsed OK
      next unless $vcf_vf && $vcf_vf->isa('Bio::EnsEMBL::Variation::VariationFeature');
      
      # compare coords
      next unless $vcf_vf->{start} == $vf->{end} && $vcf_vf->{start} == $vf->{end};
      
      # get alleles, shift off reference
      my @vcf_alleles = split /\//, $vcf_vf->allele_string;
      my $ref_allele = shift @vcf_alleles;
      
      # iterate over required headers
      foreach my $h(@{$self->{headers} || []}) {
        my $total_ac = 0;
        
        if(/$h\=([0-9\,]+)/) {
          
          # grab AC
          my @ac = split /\,/, $1;
          next unless scalar @ac == scalar @vcf_alleles;
          
          # now sed header to get AN
          my $anh = $h;
          $anh =~ s/AC/AN/;
          
          my $afh = $h;
          $afh =~ s/AC/AF/;
          
          if(/$anh\=([0-9\,]+)/) {
            
            # grab AN
            my $an = $1;            
            next unless $an;
            
            foreach my $a(@vcf_alleles) {
              my $ac = shift @ac;
              $total_ac += $ac;
              $data->{$a}->{'ExAC_'.$afh} = sprintf("%.3g", $ac / $an);
            }
            
            # use total to get ref allele freq
            $data->{$ref_allele}->{'ExAC_'.$afh} = sprintf("%.3g", 1 - ($total_ac / $an));
          }
        }
      }
    }
    
    close TABIX;
  }
  
  # overwrite cache
  $self->{cache} = {$pos_string => $data};
  
  return defined($data->{$allele}) ? $data->{$allele} : {};
}

1;

