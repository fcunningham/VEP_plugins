=head1 LICENSE
                                                                                                                     
 Copyright (c) 1999-2015 The European Bioinformatics Institute and
 Genome Research Limited.  All rights reserved.                                                                      
                                                                                                                     
 This software is distributed under a modified Apache license.                                                       
 For license details, please see

   http://www.ensembl.org/info/about/code_licence.html                                                               
                                                                                                                     
=head1 CONTACT                                                                                                       

 William McLaren <wm2@ebi.ac.uk>
    
=cut

=head1 NAME

 LoFtool

=head1 SYNOPSIS

  mv LoFtool.pm ~/.vep/Plugins
  mv LoFtool_scores.txt ~/.vep/Plugins
  perl variant_effect_predictor.pl -i variants.vcf --plugin LoFtool

=head1 DESCRIPTION

  Add LoFtool scores to the VEP output.

  LoFtool provides a rank of genic intolerance and consequent
  susceptibility to disease based on the ratio of Loss-of-function (LoF)
  to synonymous mutations for each gene in 60,706 individuals from ExAC,
  adjusting for the gene de novo mutation rate and evolutionary protein
  conservation. The lower the LoFtool gene score percentile the most
  intolerant is the gene to functional variation. Manuscript in
  preparation (please contact Dr. Joao Fadista - joao.fadista@med.lu.se).
  The authors would like to thank the Exome Aggregation Consortium and
  the groups that provided exome variant data for comparison. A full
  list of contributing groups can be found at http://exac.broadinstitute.org/about.

  The LoFtool_scores.txt file is found alongside the plugin in the
  VEP_plugins GitHub repo.

  To use another scores file, add it as a parameter i.e.

  perl variant_effect_predictor.pl -i variants.vcf --plugin LoFtool,scores_file.txt

=cut

package LoFtool;

use strict;
use warnings;

use DBI;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepPlugin);

sub new {
  my $class = shift;

  my $self = $class->SUPER::new(@_);
  
  my $file = $self->params->[0];

  if(!$file) {
    my $plugin_dir = $INC{'LoFtool.pm'};
    $plugin_dir =~ s/LoFtool\.pm//i;
    $file = $plugin_dir.'/LoFtool_scores.txt';
  }
  
  die("ERROR: LoFtool scores file $file not found\n") unless $file && -e $file;
  
  open IN, $file;
  my %scores;
  
  while(<IN>) {
    chomp;
    my ($gene, $score) = split;
    next if $score eq 'LoFtool_percentile';
    $scores{lc($gene)} = sprintf("%g", $score);
  }
  
  close IN;
  
  die("ERROR: No scores read from $file\n") unless scalar keys %scores;
  
  $self->{scores} = \%scores;
  
  return $self;
}

sub feature_types {
  return ['Transcript'];
}

sub get_header_info {
  return {
    LoFtool => "LoFtool score for gene"
  };
}

sub run {
  my $self = shift;
  my $tva = shift;
  
  my $symbol = $tva->transcript->{_gene_symbol} || $tva->transcript->{_gene_hgnc};
  return {} unless $symbol;
  
  return $self->{scores}->{lc($symbol)} ? { LoFtool => $self->{scores}->{lc($symbol)}} : {};
}

1;

