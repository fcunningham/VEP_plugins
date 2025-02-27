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

  GXA

=head1 SYNOPSIS

  mv GXA.pm ~/.vep/Plugins
  perl variant_effect_predictor.pl -i variations.vcf --cache --plugin GXA

=head1 DESCRIPTION

  This is a plugin for the Ensembl Variant Effect Predictor (VEP) that
  reports data from the Gene Expression Atlas.

  NB: no account is taken for comparing values across experiments; if values
  exist for the same tissue in more than one experiment, the highest value
  is reported.

=cut

package GXA;

use strict;
use warnings;

use Bio::EnsEMBL::Variation::Utils::BaseVepPlugin;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepPlugin);

sub new {
  my $class = shift;
  
  my $self = $class->SUPER::new(@_);
  
  $self->{species} =  $self->{config}->{species};
  $self->{species} =~ s/\_/\%20/;
  
  $self->{url} = 'https://www.ebi.ac.uk/gxa/widgets/heatmap/multiExperiment.tsv?propertyType=bioentity_identifier';
  
  return $self;
}

sub feature_types {
  return ['Transcript'];
}

sub variant_feature_types {
  return ['BaseVariationFeature'];
}

sub get_header_info {
  my $self = shift;
  
  if(!exists($self->{_header_info})) {
    
    # get tissues using BRCA2
    my $url = sprintf(
      '%s&species=%s&geneQuery=%s',
      $self->{url},
      $self->{species},
      'BRCA2'
    );
    
    open IN, "curl -s \"$url\" |";
    my @lines = <IN>;
    
    my %headers = ();
    
    while(my $line = shift @lines) {
      next if $line =~ /^#/;
      chomp $line;
      $line =~ s/ /\_/g;
      %headers = map {'GXA_'.$_ => "Tissue expression level in $_ from Gene Expression Atlas"} (split /\t/, $line);
      last;
    }
    
    close IN;
    
    $self->{_header_info} = \%headers;
  };
  
  return $self->{_header_info};
}

sub run {
  my ($self, $tva) = @_;
  
  my $tr = $tva->transcript;
  my $gene_id = $tr->{_gene_stable_id} || $tr->{_gene}->stable_id;
  return {} unless $gene_id;
  
  if(!exists($self->{_cache}) || !exists($self->{_cache}->{$gene_id})) {
    
    my $url = sprintf(
      '%s&species=%s&geneQuery=%s',
      $self->{url},
      $self->{species},
      $gene_id
    );
    
    open IN, "curl -s \"$url\" |";
    
    my $first = 1;
    my (@headers, %data);
    
    while(<IN>) {
      next if /^#/;
      chomp;
            
      if($first) {
        s/ /\_/g;
        @headers = split /\t/, $_;
        $first = 0;
      }
      else {
        my @tmp = split /\t/, $_;
        
        for(my $i=0; $i<=$#headers; $i++) {
          my ($h, $d) = ('GXA_'.$headers[$i], $tmp[$i]);
          next unless defined($d) && $d =~ /^[0-9\.]+$/;
          
          if(exists($data{$h})) {
            $data{$h} = $d if $d > $data{$h};
          }
          else {
            $data{$h} = $d;
          }
        }
      }
    }
    
    close IN;
    
    $self->{_cache}->{$gene_id} = \%data;
  }
  
  return $self->{_cache}->{$gene_id};
}

1;
