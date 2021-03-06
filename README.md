# Welcome to zUMIs :red_car::dash:

zUMIs is a fast and flexible pipeline to process RNA-seq data with UMIs.

The input to this pipeline is paired-end fastq files, where one read contains the cDNA sequence and the other read contains UMI and Cell Barcode information. Furthermore, you will need a STAR index for your genome (see below).

![zUMIs Workflow](https://github.com/sdparekh/zUMIs/blob/master/zUMIs.png?raw=true)

You can read more about zUMIs in our [paper](https://doi.org/10.1093/gigascience/giy059)!

You can glance through zUMIs in [zUMIs poster](https://github.com/sdparekh/zUMIs/blob/master/zUMIs_GI2017_poster.pdf)!

## Releases/Changelog
12 Apr 2018: [zUMIs.0.0.6 released](https://github.com/sdparekh/zUMIs/releases/tag/zUMIs.0.0.6).
Improved support for combinatorial indexing methods.

30 Mar 2018: [zUMIs.0.0.5 released](https://github.com/sdparekh/zUMIs/releases/tag/zUMIs.0.0.5).
Rewrote hamming distance binning of UMIs and barcodes. In addition to faster running times, removed dependency on the stringdist package that may have led to issues with parallel computing in some systems. Furthermore removed a possible bug when resuming running with the -w switch in combination with plate barcode usage.

23 Feb 2018: [zUMIs.0.0.4 released](https://github.com/sdparekh/zUMIs/releases/tag/zUMIs.0.0.4).
Added support for plate barcodes with input of an additional barcode fastq file (eg. Illumina i7 index read). Addition of version number in zUMIs-master. Parameters are printed in a .zUMIs_run.txt file for each call.

18 Feb 2018: [zUMIs.0.0.3 released](https://github.com/sdparekh/zUMIs/releases/tag/zUMIs.0.0.3).
Switched support to the new Rsubread version and data format. Furthermore to compensate sequencing/PCR errors, zUMIs now features UMI correction using Hamming distance and binning of adjacent cell barcodes.

You can find the older versions of zUMIs [here](https://github.com/sdparekh/zUMIs/releases/).

## Installation and Usage

Please find information on [installation](https://github.com/sdparekh/zUMIs/wiki/Installation) and [usage](https://github.com/sdparekh/zUMIs/wiki/Usage) in the [zUMIs wiki](https://github.com/sdparekh/zUMIs/wiki/).

## Compatibility

zUMIs is compatible with these single-cell UMI protocols:

- CEL-seq with UMI (Grün et al., 2014)
- SCRB-seq (Soumillon et al., 2014)
- MARS-seq (Jaitin et al., 2014)
- STRT-C1 (Islam et al., 2014)
- Drop-seq (Macosko et al., 2015)
- CEL-seq2 (Hashimshony et al., 2016)
- SORT-seq (Muraro et al., 2016)
- DroNc-seq (Habib et al., 2017)
- Seq-Well (Gierahn et al., 2017)
- SPLiT-seq (Rosenberg et al., 2018)
- sci-RNA-seq (Cao et al., 2017)
- STRT-2i (Hochgerner et al., 2018)
- Quartz-seq2 (Sasagawa et al., 2017)
- 10x Genomics Chromium (Zheng et al., 2017)
- Wafergen ICELL8 (Gao et al., 2017)
- Illumina ddSEQ SureCell
- inDrops (Zilionis et al., 2017; Klein et al. 2015)

For combinatorial indexing protocols, be sure to [check our wiki page](https://github.com/sdparekh/zUMIs/wiki/Combinatorial-Indexing).

If you do not find your (favorite) scRNA-seq protocol on the list, get in touch with us!

## Getting help

Refer to [zUMIs Github wiki](https://github.com/sdparekh/zUMIs/wiki) for help.

Feel free to contact us on Twitter [@swatidparekh](https://twitter.com/swatidparekh) and [@chris_zie](https://twitter.com/chris_zie) with comments or questions!

Please report bugs :beetle::bug: to the [zUMIs Github issue page](https://github.com/sdparekh/zUMIs/issues)

If you encounter issues when using zUMIs for the first time, please try to [run the example data set](https://github.com/sdparekh/zUMIs/wiki/Usage) included in this repository.
