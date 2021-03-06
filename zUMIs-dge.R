#!/usr/bin/env Rscript

require(optparse)

# optparse  ---------------------------------------------------------------

option_list = list(
  make_option(c("--gtf"), type="character", default=NULL,
              help="GTF file", metavar="character"),
  make_option(c("--abam"), type="character", default=NULL,
              help="STAR Aligned bam file", metavar="character"),
  make_option(c("--ubam"), type="character", default=NULL,
              help="XC/XM read unaligned sam file", metavar="character"),
  make_option(c("--barcodefile"), type="character", default=NULL,
              help="A file with a list of cell barcodes without a header", metavar="character"),
  make_option(c("--barcodenumber"), type="integer", default=NULL,
              help="number of highest barcodes to take", metavar="integer"),
  make_option(c("--out"), type="character", default=NULL,
              help="output directory", metavar="character"),
  make_option(c("--sn"), type="character", default="study",
              help="Study name", metavar="character"),
  make_option(c("--cores"), type="integer", default=10,
              help="Number of threads", metavar="integer"),
  make_option(c("--strandedness"), type="integer", default=0,
              help="0 unsranded, 1 stranded, 2 reverse stranded", metavar="integer"),
  make_option(c("--bcstart"), type="integer", default=1,
              help="Start position of cell barcode in the read", metavar="integer"),
  make_option(c("--bcend"), type="integer", default=6,
              help="End position of cell barcode in the read", metavar="integer"),
  make_option(c("--umistart"), type="integer", default=7,
              help="Start position of UMI in the read", metavar="integer"),
  make_option(c("--umiend"), type="integer", default=16,
              help="End position of UMI barcode in the read", metavar="integer"),
  make_option(c("--subsamp"), type="character", default="0",
              help="Number of reads for downsampling.", metavar="character"),
  make_option(c("--nReadsBC"), type="integer", default="100",
              help="Retain cells with atleast N reads.", metavar="integer"),
  make_option(c("--hamming"), type="character", default=0,
                          help="Hamming distance filter", metavar="integer"),
  make_option(c("--XCbin"), type="character", default=0,
                          help="Hamming distance of XC binning", metavar="integer")
);

opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

print("I am loading useful packages...")
print(Sys.time())
packages <-c("multidplyr","dplyr","tidyr","broom","reshape2","data.table","optparse","parallel","methods","GenomicRanges","GenomicFeatures","GenomicAlignments","AnnotationDbi","ggplot2","cowplot","tibble","mclust","Matrix","Rsubread")
paks<-lapply(packages, function(x) suppressMessages(require(x, character.only = TRUE)))
rm(paks)

 #Check the version of Rsubread
if(length(grep("Rsubread",installed.packages()))==0){
   print("I did not find Rsubread so I am installing it...")
   BiocInstaller::biocLite("Rsubread",dependencies = TRUE, ask = FALSE)
 }else{
   if(all(as.numeric_version(installed.packages()[grep("Rsubread",installed.packages()),"Version"])<'1.26.1')){
     print("I need newer Rsubread so I am updating it...")
     BiocInstaller::biocUpdatePackages("Rsubread", ask=FALSE)
   }
}
suppressMessages(require("Rsubread"))

ncores=opt$cores
bcstart=opt$bcstart
bcend=opt$bcend
umistart=opt$umistart
umiend=opt$umiend
stra=opt$strandedness
subsampling=opt$subsamp
sn=opt$sn
out=opt$out
HamDist=opt$hamming
nReadsBC=opt$nReadsBC
XCbin=opt$XCbin
if(is.null(opt$barcodefile)==F){
  if(opt$barcodefile=="NA"){
    barcodes <- NA
  }else if(file.exists(opt$barcodefile)){
    barcodes<-opt$barcodefile
  }else{
    print("The barcodes file does not exist!")
    q()
  }
}else if( is.null(opt$barcodenumber)==F){
  barcodes<-opt$barcodenumber
}else if(is.null(opt$barcodenumber)==F & is.null(opt$barcodefile)==F){
  barcodes<-opt$barcodefile
}else if(is.null(opt$barcodenumber)==T & is.null(opt$barcodefile)==T){
  print("Provide either barcodes file or number of barcodes to choose.")
  q()
}else{
  print("Provide either barcodes file or number of barcodes to choose.")
  q()
}

if(is.null(opt$abam)==F){
  abamfile <- opt$abam
}else{
  print("Provide an aligned bam file with unmapped reads within.")
  q()
}

if(is.null(opt$ubam)==F){
  ubamfile <- opt$ubam
}else{
  print("Provide an unalinged SAM file of barcode reads.")
  q()
}

if(is.null(opt$gtf)==F){
  gtf <- opt$gtf
}else{
  print("Provide a GTF file please.")
  q()
}



setwd(dirname(abamfile))
#################

# make SAF of intron/exon/intron&exon -------------------------------------

print("I am making annotations in SAF... This will take less than 3 minutes...")
print(Sys.time())

txdb <- GenomicFeatures::makeTxDbFromGFF(file=gtf, format="gtf")

## Make Gene-range GR-object
se <- AnnotationDbi::select(txdb, keys(txdb, "GENEID"),
                            columns=c("GENEID","TXCHROM","TXSTART","TXEND","TXSTRAND"),
                            keytype="GENEID") %>%
  dplyr::group_by(GENEID,TXCHROM,TXSTRAND)  %>%
  dplyr::mutate( txstart =ifelse(TXSTART<TXEND,min(TXSTART),min(TXEND)),
                 txend  =ifelse(TXSTART<TXEND,max(TXEND),min(TXSTART) ) ) %>%
  dplyr::select(GENEID,TXCHROM,TXSTRAND,txstart,txend)  %>% unique()


gr.gene<-GenomicRanges::GRanges(seqnames = se$TXCHROM,
                 ranges =  IRanges(start= se$txstart,
                                   end=  se$txend,
                                   names=se$GENEID),
                 strand =  se$TXSTRAND,
                 gid    =  se$GENEID)

### Get non-overlapping Introns/Exons
intron<-GenomicFeatures::intronsByTranscript(txdb, use.names=T)
exon<-GenomicFeatures::exonsBy(txdb, by="tx",use.names=T)

intron.exon.red <- c( GenomicRanges::reduce(unlist(intron),ignore.strand=T), GenomicRanges::reduce(unlist(exon),ignore.strand=T) )
intron.exon.dis <- GenomicRanges::disjoin(intron.exon.red, ignore.strand=T)
intron.only<-GenomicRanges::setdiff(intron.exon.dis, unlist(exon) ,ignore.strand=T)

ol.in<-GenomicRanges::findOverlaps(intron.only, gr.gene, select="arbitrary")
ol.ex<-GenomicRanges::findOverlaps(unlist(exon), gr.gene, select="arbitrary")

intron.saf<-data.frame(GeneID= names(gr.gene)[ol.in],
		       Chr   = seqnames(intron.only),
		       Start = start(intron.only),
		       End	 =   end(intron.only),stringsAsFactors = F)
exon.saf<-data.frame(GeneID= names(gr.gene)[ol.ex],
		     Chr   = seqnames(unlist(exon)),
		     Start = start(unlist(exon)),
		     End	 =   end(unlist(exon)),
		     Strand =  strand(unlist(exon)),stringsAsFactors = F)

intron.saf<-dplyr::left_join(intron.saf,unique(exon.saf[,c("GeneID","Strand")]),by=c("GeneID"))

saf <- list(introns=intron.saf,exons=exon.saf)
safout <- paste(out,"/zUMIs_output/expression/",sn,".annotationsSAF.rds",sep="")

saveRDS(saf, file=safout)
rm(se,gr.gene,intron,exon,intron.exon.red,intron.exon.dis,intron.only,ol.ex,ol.in,intron.saf,exon.saf)
#################

print("I am making count tables...This will take a while!!")
print(Sys.time())


# make umi and read count tables ------------------------------------------
makeGEprofile <- function(abamfile,ubamfile,bcfile,safannot,ncores,stra,bcstart,bcend,umistart,umiend,subsampling,ftype,sn,out,nReadsBC){

  makewide <- function(longdf,nbc,type){
      print("I am making a sparseMatrix!!")
      longdf$XC <- as.factor(longdf$XC)
      longdf$GE <- as.factor(longdf$GE)
      widedf <- Matrix::sparseMatrix(i=as.integer(longdf$GE), j=as.integer(longdf$XC), x=as.numeric(pull(longdf[,type])), dimnames=list(levels(longdf$GE), levels(longdf$XC)))
    return(widedf)
  }

  BCselection <- function(fullstats){
    tmp<-mclust::Mclust(log10(fullstats$nreads), modelNames = c("E","V"))
    ss <- ifelse(tmp$modelName=="E",1,tmp$G)
    mm<-tmp$parameters$mean[tmp$G]
    va<-tmp$parameters$variance$sigmasq[ss]

    cut<-10^(qnorm(0.01, m=mm,sd=sqrt(va)))
    rcfilt <- fullstats[fullstats$nreads>=cut,]
    return(rcfilt)
  }

  ham_twomats <- function(barcodes,XCstrings) {
    barcodes<-as.character(barcodes) #make sure this is a character, not a factor
    X<- matrix(unlist(strsplit(barcodes, "")),ncol = length(barcodes))
    Y<- matrix(unlist(strsplit(XCstrings, "")),ncol = length(XCstrings))

    #function below thanks to Johann de Jong
    #https://goo.gl/u8RBBZ
    uniqs <- union(X, Y)
    H <- t(X == uniqs[1]) %*% (Y == uniqs[1])
    for ( uniq in uniqs[-1] ) {
      H <- H + t(X == uniq) %*% (Y == uniq)
    }
    nrow(X) - H
  }

  hammingFilter<-function(umiseq, edit=1){
    ham_mat <- function(umistrings) {
      X<- matrix(unlist(strsplit(umistrings, "")),ncol = length(umistrings))
      #function below thanks to Johann de Jong
      #https://goo.gl/u8RBBZ
      uniqs <- unique(as.vector(X))
      U <- X == uniqs[1]
      H <- t(U) %*% U
      for ( uniq in uniqs[-1] ) {
        U <- X == uniq
        H <- H + t(U) %*% U
      }
      nrow(X) - H
    }
    library(dplyr) #necessary for pipe to work within multidplyr workers
    # umiseq a vector of umis, one per read
    umiseq <- sort(umiseq)
    uc     <- data.frame(us = umiseq,stringsAsFactors = F) %>% dplyr::count(us) # normal UMI counts

    if(length(uc$us)>1 && length(uc$us)<100000){ #prevent use of > 100Gb RAM
      Sys.time()
      umi <-  ham_mat(uc$us) #construct pairwise UMI distances
      umi[upper.tri(umi,diag=T)] <- NA #remove upper triangle of the output matrix
      umi <- reshape2::melt(umi, varnames = c('row', 'col'), na.rm = TRUE) %>% dplyr::filter( value <= edit  ) #make a long data frame and filter according to cutoff
      umi$n.1 <- uc[umi$row,]$n #add in observed freq
      umi$n.2 <- uc[umi$col,]$n#add in observed freq
      umi <- umi %>%dplyr::transmute( rem=if_else( n.1>=n.2, col, row )) %>%  unique() #discard the UMI with fewer reads
      if(nrow(umi)>0){
        uc <- uc[-umi$rem,] #discard all filtered UMIs
      }
    }
    n <- nrow(uc)
    return(n)
  }

  if(ftype == "inex"){

    fctsfilein <- data.table::fread(paste("cut -f2,4 ",abamfile[1],".featureCounts",sep=""), sep="\t",quote='',header = F) #in
    fctsfileex <- data.table::fread(paste("cut -f2,4 ",abamfile[2],".featureCounts",sep=""), sep="\t",quote='',header = F) #ex
    reads <- data.table::fread(paste("cut -f10 ",ubamfile,sep=""), quote='',header = F,skip=1)
    reads <- tibble::tibble(XC=substring(reads$V1, bcstart, bcend),XM=substring(reads$V1, umistart, umiend),GE=fctsfileex$V2,assignment=fctsfileex$V1,ftype="exon")
    fctsfilein$ftype<-"intron"
    reads[which(is.na(reads$GE)),c("GE","assignment","ftype")] <- fctsfilein[which(is.na(reads$GE)),c("V2","V1","ftype")]
    reads$ftype <- ifelse(reads$assignment=="Assigned",reads$ftype,"inex")
    saveRDS(object = reads,file = paste(out,"/zUMIs_output/expression/",sn,".tbl.rds",sep=""))
  } else{

    fcts <-  Rsubread::featureCounts(files=substr(x=abamfile[1],start=1,stop=nchar(abamfile[1])-3),annot.ext=safannot[[1]],isGTFAnnotationFile=F,primaryOnly=T,nthreads=1,reportReads="CORE",strandSpecific=stra)# do not use more than nthreads=1!
    system(command=paste("mv ",substr(x=abamfile[1],start=1,stop=nchar(abamfile[1])-3),".featureCounts ",abamfile[1],".featureCounts",sep=""))
    fcts <-  Rsubread::featureCounts(files=substr(x=abamfile[2],start=1,stop=nchar(abamfile[2])-3),annot.ext=safannot[[2]],isGTFAnnotationFile=F,primaryOnly=T,nthreads=1,reportReads="CORE",strandSpecific=stra)# do not use more than nthreads=1!
    system(command=paste("mv ",substr(x=substr(x=abamfile[2],start=1,stop=nchar(abamfile[2])-3),start=1,stop=nchar(abamfile[2])-3),".featureCounts ",abamfile[2],".featureCounts",sep=""))

    fctsfile <- data.table::fread(paste("cut -f4 ",abamfile[2],".featureCounts",sep=""), sep="\t",quote='',header = F)
    reads <- data.table::fread(paste("cut -f10 ",ubamfile,sep=""), quote='',header = F,skip=1)

    reads <- tibble::tibble(XC=substring(reads$V1, bcstart, bcend),XM=substring(reads$V1, umistart, umiend),GE=fctsfile$V1)


     if(is.na(bcfile)){
      fullstats <- reads %>% dplyr::group_by(XC) %>% dplyr::summarise(nreads=length(XM))
      fullstats<-fullstats[fullstats$nreads>=nReadsBC,]
      fullstats <- fullstats[order(fullstats$nreads,decreasing = T),]
      fullstats$cs <- cumsum(fullstats$nreads)
      fullstats$cellindex <- seq(1:nrow(fullstats))
      fullstats_detected <- BCselection(fullstats)

      if(nrow(fullstats_detected)<10){
        print("Attention! Adaptive BC selection gave < 10 cells so I will now use top 100 cells!")
        bc <<- reads %>% dplyr::group_by(XC) %>% dplyr::summarise(n=length(XM))  %>% dplyr::top_n(100) %>% dplyr::select(V1=XC)
        fullstats_detected<- fullstats[which(fullstats$XC %in% bc$V1),]
      }else{
        print(paste(nrow(fullstats_detected)," barcodes detected.",sep=""))
        bc <<- data.frame(V1=fullstats_detected$XC)
      }

      #selected cells
      fullstats$col<-1
      fullstats[which(fullstats$XC %in% fullstats_detected$XC),"col"] <- 2

      p_dens<-ggplot2::ggplot(fullstats,aes(x=log10(nreads)))+geom_density()+theme_classic()+geom_vline(xintercept = log10(min(fullstats_detected$nreads)),col="#56B4E9",size=1.5)+xlab("log10(Number of reads per cell)")+ylab("Density")+ggtitle("Cells right to the blue line are selected")+theme(axis.text = element_text(size=12),axis.title = element_text(size=13),plot.title = element_text(hjust=0.5,vjust=0.5,size=13))

      p_bc<-ggplot2::ggplot(fullstats,aes(y=cs,x=cellindex,color=col))+geom_point(size=2)+xlab("Cell Index")+ ylab("Cumulative number of reads")+ggtitle("Detected cells are highlighted in blue")+theme_classic()+theme(legend.position = "none",legend.text = element_text(size=15),legend.title = element_blank(),axis.text = element_text(size=12),axis.title = element_text(size=13),plot.title = element_text(hjust=0.5,vjust=0.5,size=13))

      bcplot <- cowplot::plot_grid(p_dens,p_bc,labels = c("a","b"))

      ggplot2::ggsave(bcplot,filename=paste(out,"/zUMIs_output/stats/",sn,".detected_cells.pdf",sep=""),width = 10,height = 4)

        }else{
          if(is.numeric(bcfile)){
            fullstats_detected <- reads %>% dplyr::group_by(XC) %>% dplyr::summarise(nreads=length(XM)) %>% dplyr::top_n(bcfile)
            bc <<- data.frame(V1=fullstats_detected$XC)
          }else{
            bc <<- read.table(bcfile,header = F,stringsAsFactors = F)
          }
    }
  }
  ## XC binning below
  if(XCbin != 0){
    XC_obs<-unique(reads$XC)
    if(as.numeric(length(XC_obs))*as.numeric(length(bc$V1)) > 1e+10){
      print("There are too many noisy barcodes, binning will be skipped")
    }else{
      print(paste("I am binning cell barcodes within hamming distance ",XCbin,sep=""))
      paste("This may be slow, depending on the number of reads")
      binmat <- ham_twomats(bc$V1,XC_obs)
      tmp <- reshape2::melt(binmat) %>% dplyr::mutate_if(is.factor, as.character) %>% dplyr::filter(value>0 & value <=XCbin)
      tmp$Var1<-bc$V1[tmp$Var1]
      tmp$Var2<-XC_obs[tmp$Var2]
      if(XCbin > 1){ #if there are conflicts we can choose the closer ones for dists >1
        dups <- tmp$Var2[duplicated(tmp$Var2)]
        for(i in dups){
          tmpdists<-tmp[which(tmp$Var2==i),"value"]
          if(min(tmpdists)==max(tmpdists)){ #if the dups are all with same dist
            binnable <- tmp[-which(tmp$Var2==i),] #..remove them
          }else{
            binnable <- tmp[-which(tmp$Var2==i & tmp$value>min(tmpdists)),] #keep only the minimal distance
            if(nrow(binnable[which(binnable$Var2==i),])>1){ #if still more than one possibility
              binnable <- binnable[-which(binnable$Var2==i),] #...remove them
            }
          }
        }
      }else{
        dups <- tmp$Var2[duplicated(tmp$Var2)]
        binnable <- tmp$Var2[!(tmp$Var2 %in% dups)] #avoid conflicts
      }
      print(paste(length(binnable)," adjacent barcodes will be binned",sep=""))
      for(i in 1:nrow(binmat)){
        tobin<-names(which(binmat[i,]>0 & binmat[i,]<=XCbin))
        tobin<-tobin[which(tobin %in% binnable)]
        if(length(tobin)>0){
          reads[which(reads$XC %in% tobin),"XC"] <- row.names(binmat)[i]
        }
      }
      saveRDS(object = reads,file = paste(out,"/zUMIs_output/expression/",sn,".XCbinned.tbl.rds",sep=""))
    }
  }
  ## end XC binning

  if(HamDist==0){
    umicounts <- reads %>% dplyr::filter((XC %in% bc$V1) & (!is.na(GE))) %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))
  }else{
    cluster <- create_cluster(ncores) # The clustering may have issues in partition when there is not enough data to spread on all the cores.
    set_default_cluster(cluster)
    cluster_copy(cluster, hammingFilter)
    cluster_copy(cluster, HamDist)
    umicounts <- reads %>% dplyr::filter((XC %in% bc$V1) & (!is.na(GE))) %>% multidplyr::partition(XC, cluster = cluster) %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
  }

  if(subsampling!="0") {
    if(grepl(pattern = ",",x = subsampling)==TRUE){
      tmpsplit <- strsplit(x = subsampling,split = ",")[[1]]
      ndepths <- length(tmpsplit)

    }else{
      ndepths <- 1
      tmpsplit <- subsampling
    }
    downsampling_list <-list()
    for(i in 1:ndepths){
      subsampling_iter <- tmpsplit[i]
      if(grepl(pattern = "-",x = subsampling_iter)==TRUE){
        subsampling_min <- as.numeric(strsplit(subsampling_iter,"-")[[1]][1])
        subsampling_max <- as.numeric(strsplit(subsampling_iter,"-")[[1]][2])

        if(as.logical((nrow(reads %>% dplyr::group_by(XC) %>% dplyr::summarise(n=length(XM)) %>% dplyr::filter(n>=subsampling_min))) >= 2)==TRUE){
          print(paste("I am subsampling to ",subsampling_iter,sep=""))
          if(HamDist==0){
            tmp1 <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) > subsampling_max) %>% dplyr::sample_n(size = subsampling_max,replace=F)%>% dplyr::filter(!is.na(GE))  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))

            tmp2 <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter((length(XC) < subsampling_max) & (length(XC) >= subsampling_min))%>% dplyr::filter(!is.na(GE))  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))
          }else{
            tmp1 <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) > subsampling_max) %>% dplyr::sample_n(size = subsampling_max,replace=F)%>% dplyr::filter(!is.na(GE))
            if(nrow(tmp1)>0){
                tmp1 %>% multidplyr::partition(XC, cluster = cluster) %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
              }
            tmp2 <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter((length(XC) < subsampling_max) & (length(XC) >= subsampling_min))%>% dplyr::filter(!is.na(GE)) %>% multidplyr::partition(XC, cluster = cluster)  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
          }
          umicounts_sub <- dplyr::bind_rows(tmp1,tmp2)
        }else{
          print("Error! None of the barcodes has more than the requested minimal number of reads")
        }
      }else{
        subsampling_no <- as.numeric(subsampling_iter)
        if(as.logical((nrow(reads %>% dplyr::group_by(XC) %>% dplyr::summarise(n=length(XM)) %>% dplyr::filter(n>=subsampling_no))) >= 2)==TRUE){
          print(paste("I am subsampling to ",subsampling_iter,sep=""))
          if(HamDist==0){
            umicounts_sub <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) >= subsampling_no) %>% dplyr::sample_n(size = subsampling_no,replace=F)%>% dplyr::filter(!is.na(GE))  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))
          }else{
            umicounts_sub <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) >= subsampling_no) %>% dplyr::sample_n(size = subsampling_no,replace=F)%>% dplyr::filter(!is.na(GE)) %>% multidplyr::partition(XC, cluster = cluster) %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
          }
        }else{
          print("Error! None of the barcodes has more than the requested number of reads")
        }
      }

      umicounts_sub_wide <- makewide(umicounts_sub,length(bc$V1),"umicount")
      readcounts_sub_wide <- makewide(umicounts_sub,length(bc$V1),"readcount")
      iterlist <- list(readcounts_sub_wide,umicounts_sub_wide)
      names(iterlist) <-c("readcounts_downsampled","umicounts_downsampled")
      downsampling_list[[i]] <- iterlist

    }
    if(ndepths==1){
      names(downsampling_list) <- paste("downsampled",subsampling,sep="_")
    }else{
      names(downsampling_list) <- paste("downsampled",tmpsplit,sep="_")
    }
  }else{
    fullstats <- reads %>% dplyr::group_by(XC) %>% dplyr::summarise(nreads=length(XM))
    fullstats <- fullstats[order(fullstats$nreads,decreasing = T),]
    fullstats$cs <- cumsum(fullstats$nreads)

    bcs_detected <- bc$V1
    fullstats_detected<- fullstats[which(fullstats$XC %in% bc$V1),]

    medianreads <- round(median(fullstats_detected$nreads),digits = 0)
    MAD_up <- 10^(log10(medianreads) + 3*median(abs(log10(fullstats_detected$nreads)-median(log10(fullstats_detected$nreads)))))
    MAD_low <- 10^(log10(medianreads) - 3*median(abs(log10(fullstats_detected$nreads)-median(log10(fullstats_detected$nreads)))))
    #check that low is not under 0
    if(MAD_low<0){
      MAD_low <- 0
    }
    MAD_up <- round(MAD_up,digits = 0)
    MAD_low <- round(MAD_low,digits = 0)

    print(paste("I am subsampling between ",MAD_low," and ",MAD_up," reads per barcode.",sep=""))
    if(HamDist==0){
      tmp1 <- reads %>% dplyr::filter(XC %in% bcs_detected)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) > MAD_up) %>% dplyr::sample_n(size = MAD_up,replace=F) %>% dplyr::filter(!is.na(GE))  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))
      tmp2 <- reads %>% dplyr::filter(XC %in% bcs_detected)  %>% dplyr::group_by(XC) %>% dplyr::filter((length(XC) >= MAD_low )& (length(XC) <= MAD_up)) %>% dplyr::filter(!is.na(GE))  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=length(unique(XM)),readcount=length(XM))
    }else{
      tmp1 <- reads %>% dplyr::filter(XC %in% bc$V1)  %>% dplyr::group_by(XC) %>% dplyr::filter(length(XC) > MAD_up) %>% dplyr::sample_n(size = MAD_up,replace=F)%>% dplyr::filter(!is.na(GE))
      if(nrow(tmp1)>0){
          tmp1 %>% multidplyr::partition(XC, cluster = cluster) %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
        }
      tmp2 <- reads %>% dplyr::filter(XC %in% bcs_detected)  %>% dplyr::group_by(XC) %>% dplyr::filter((length(XC) >= MAD_low )& (length(XC) <= MAD_up)) %>% dplyr::filter(!is.na(GE))  %>% multidplyr::partition(XC, cluster = cluster)  %>% dplyr::group_by(XC,GE) %>% dplyr::summarise(umicount=hammingFilter(XM,edit = HamDist),readcount=length(XM)) %>% dplyr::collect()
    }
    umicounts_sub <- dplyr::bind_rows(tmp1,tmp2)

    downsampling_list <-list()
    umicounts_sub_wide <- makewide(umicounts_sub,length(bc$V1),"umicount")
    readcounts_sub_wide <- makewide(umicounts_sub,length(bc$V1),"readcount")
    iterlist <- list(readcounts_sub_wide,umicounts_sub_wide)
    names(iterlist) <-c("readcounts_downsampled","umicounts_downsampled")
    downsampling_list[[1]] <- iterlist
    names(downsampling_list) <- paste("downsampled",medianreads,sep="_")

    #downsampling
    #check if ranges include MAD max
    pdf(file=paste(out,"/zUMIs_output/stats/",sn,".downsampling_thresholds.pdf",sep=""))
    barplot(fullstats_detected$nreads,ylab="Number of reads",xlab="Cell Barcodes",ylim = c(0,1.1*max(c(fullstats_detected$nreads,MAD_up))))
    abline(h=MAD_low,col="red")
    abline(h=MAD_up,col="red")
    dev.off()
  }

  umicounts_wide <- makewide(umicounts,length(bc$V1),"umicount")

  readcounts_wide <- makewide(umicounts,length(bc$V1),"readcount")


  l <- list(readcounts_wide,umicounts_wide,downsampling_list)
  names(l) <- c("readcounts","umicounts","downsampled")


  rm(reads,readcounts_wide,umicounts,umicounts_wide)

  return(l)
}

ftype <- c("in","ex","inex")

bams <- c(paste(abamfile,"in",sep="."),paste(abamfile,"ex",sep="."))

AllCounts <-list()
AllCounts$exons <- makeGEprofile(bams,ubamfile,barcodes,saf,ncores,stra,bcstart,bcend,umistart,umiend,subsampling,ftype[2],sn,out,nReadsBC)

AllCounts$intron.exon <- makeGEprofile(bams,ubamfile,barcodes,saf[[1]],ncores,stra,bcstart,bcend,umistart,umiend,subsampling,ftype[3],sn,out,nReadsBC)


intronunique <- function(intronexondf,exondf){
  ex_in_gene_intersect <- base::intersect(row.names(intronexondf),row.names(exondf))
  ex_in_cell_intersect <- base::intersect(colnames(intronexondf),colnames(exondf))

  uniquein <- rbind(intronexondf[which(!(row.names(intronexondf) %in% row.names(exondf))),ex_in_cell_intersect],
                    (intronexondf[ex_in_gene_intersect,ex_in_cell_intersect] - exondf[ex_in_gene_intersect,ex_in_cell_intersect])
  )
  uniquein <- uniquein[which(rowSums(uniquein)>0),]
  return(uniquein)
}

AllCounts$introns$umicounts <- intronunique(AllCounts$intron.exon$umicounts,AllCounts$exons$umicounts)
AllCounts$introns$readcounts <- intronunique(AllCounts$intron.exon$readcounts,AllCounts$exons$readcounts)

tmpintersect <- base::intersect(row.names(AllCounts$introns$umicounts),row.names(AllCounts$introns$readcounts))
AllCounts$introns$umicounts <- AllCounts$introns$umicounts[tmpintersect,]
AllCounts$introns$readcounts <- AllCounts$introns$readcounts[tmpintersect,]
rm(tmpintersect)

if(subsampling!= "0") {
  print("I am making intronunique...")
  if(grepl(pattern = ",",x = subsampling)==TRUE){
    tmpsplit <- strsplit(x = subsampling,split = ",")[[1]]
    ndepths <- length(tmpsplit)

  }else{
    ndepths <- 1
  }
  for(n in ndepths){
    AllCounts$introns$downsampled[[n]]$umicounts_downsampled <- intronunique(AllCounts$intron.exon$downsampled[[n]]$umicounts_downsampled,AllCounts$exons$downsampled[[n]]$umicounts_downsampled)

    AllCounts$introns$downsampled[[n]]$readcounts_downsampled <- intronunique(AllCounts$intron.exon$downsampled[[n]]$readcounts_downsampled,AllCounts$exons$downsampled[[n]]$readcounts_downsampled)

    tmpintersect <- base::intersect(row.names(AllCounts$introns$downsampled[[n]]$umicounts_downsampled),row.names(AllCounts$introns$downsampled[[n]]$readcounts_downsampled))
    AllCounts$introns$downsampled[[n]]$umicounts_downsampled <- AllCounts$introns$downsampled[[n]]$umicounts_downsampled[tmpintersect,]
    AllCounts$introns$downsampled[[n]]$readcounts_downsampled <- AllCounts$introns$downsampled[[n]]$readcounts_downsampled[tmpintersect,]
    rm(tmpintersect)
  }
}

saveRDS(AllCounts,file=paste(out,"/zUMIs_output/expression/",sn,".dgecounts.rds",sep=""))

#################

print(Sys.time())
print(paste("I am done!! Look what I produced...",out,"/zUMIs_output/",sep=""))
print(gc())
q()
