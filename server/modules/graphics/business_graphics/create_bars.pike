#!/usr/local/bin/pike
#define max(i, j) (((i)>(j)) ? (i) : (j))
#define min(i, j) (((i)<(j)) ? (i) : (j))
#define abs(arg) ((arg)*(1-2*((arg)<0)))

#define PI 3.14159265358979
//inherit Stdio;

import Image;
import Array;
import Stdio;
inherit "polyline.pike";
constant LITET = 1.0e-40;
constant STORT = 1.0e40;

inherit "create_graph.pike";



mapping(string:mixed) create_bars(mapping(string:mixed) diagram_data)
{
  //Supportar bara xsize>=100
  int si=diagram_data["fontsize"];

  string where_is_ax;

  object(image) barsdiagram;
  if (diagram_data["bgcolor"])
    barsdiagram=image(diagram_data["xsize"],diagram_data["ysize"],
		@(diagram_data["bgcolor"]));
  else
  {
    barsdiagram=diagram_data["image"];
    diagram_data["xsize"]=diagram_data["image"]->xsize();
    diagram_data["ysize"]=diagram_data["image"]->ysize();
  }
  
  diagram_data["image"]=barsdiagram;
  set_legend_size(diagram_data);

  //write("ysize:"+diagram_data["ysize"]+"\n");
  diagram_data["ysize"]-=diagram_data["legend_size"];
  //write("ysize:"+diagram_data["ysize"]+"\n");
  
  //Best�m st�rsta och minsta datav�rden.
  init(diagram_data);

  //Ta reda hur m�nga och hur stora textmassor vi ska skriva ut
  if (!(diagram_data["xspace"]))
    {
      //Initera hur l�ngt det ska vara emellan.
      
      float range=(diagram_data["xmaxvalue"]-
		 diagram_data["xminvalue"]);
      //write("range"+range+"\n");
      float space=pow(10.0, floor(log(range/3.0)/log(10.0)));
      if (range/space>5.0)
	{
	  if(range/(2.0*space)>5.0)
	    {
	      space=space*5.0;
	    }
	  else
	    space=space*2.0;
	}
      diagram_data["xspace"]=space;      
    }
  if (!(diagram_data["yspace"]))
    {
      //Initera hur l�ngt det ska vara emellan.
      
      float range=(diagram_data["ymaxvalue"]-
		 diagram_data["yminvalue"]);
      float space=pow(10.0, floor(log(range/3.0)/log(10.0)));
      if (range/space>5.0)
	{
	  if(range/(2.0*space)>5.0)
	    {
	      space=space*5.0;
	    }
	  else
	    space=space*2.0;
	}
      diagram_data["yspace"]=space;      
    }
 


  if (1)
    {
      float start;
      start=diagram_data["xminvalue"]+diagram_data["xspace"]/2.0;
      diagram_data["values_for_xnames"]=allocate(sizeof(diagram_data["xnames"]));
      for(int i=0; i<sizeof(diagram_data["xnames"]); i++)
	diagram_data["values_for_xnames"][i]=start+start*2*i;
    }
  if (!(diagram_data["values_for_ynames"]))
    {
      float start;
      start=diagram_data["yminvalue"];
      start=diagram_data["yspace"]*ceil((start)/diagram_data["yspace"]);
      diagram_data["values_for_ynames"]=({start});
      while(diagram_data["values_for_ynames"][-1]<=
	    diagram_data["ymaxvalue"]-diagram_data["yspace"])
	diagram_data["values_for_ynames"]+=({start+=diagram_data["yspace"]});
    }
  
  //Generera texten om den inte finns
  if (!(diagram_data["ynames"]))
    {
      diagram_data["ynames"]=
	allocate(sizeof(diagram_data["values_for_ynames"]));
      
      for(int i=0; i<sizeof(diagram_data["values_for_ynames"]); i++)
	diagram_data["ynames"][i]=no_end_zeros((string)(diagram_data["values_for_ynames"][i]));
    }
  if (!(diagram_data["xnames"]))
    {
      diagram_data["xnames"]=
	allocate(sizeof(diagram_data["values_for_xnames"]));
      
      for(int i=0; i<sizeof(diagram_data["values_for_xnames"]); i++)
	diagram_data["xnames"][i]=no_end_zeros((string)(diagram_data["values_for_xnames"][i]));
    }


  //rita bilderna f�r texten
  //ta ut xmaxynames, ymaxynames xmaxxnames ymaxxnames
  create_text(diagram_data);

  //Skapa labelstexten f�r xaxlen
  object labelimg;
  string label;
  int labelx=0;
  int labely=0;
  if (diagram_data["labels"])
    {
      //      if (diagram_data["labels"][2] && sizeof(diagram_data["labels"][2]))
      //label=diagram_data["labels"][0]+" ["+diagram_data["labels"][2]+"]"; //Xstorhet
      //else
      label=diagram_data["labels"][0];
      if ((label!="")&&(label!=0))
	labelimg=get_font("avant_garde", 32, 0, 0, "left",0,0)->
	  write(label)
#ifndef ROXEN
->scale(0,diagram_data["labelsize"])
#endif
;
      else
	labelimg=image(diagram_data["labelsize"],diagram_data["labelsize"]);
      labely=diagram_data["labelsize"];
      labelx=labelimg->xsize();
    }



  int ypos_for_xaxis; //avst�nd NERIFR�N!
  int xpos_for_yaxis; //avst�nd fr�n h�ger
  //Best�m var i bilden vi f�r rita graf
  diagram_data["ystart"]=(int)ceil(diagram_data["linewidth"]);
  diagram_data["ystop"]=diagram_data["ysize"]-
    (int)ceil(diagram_data["linewidth"]+si)-diagram_data["labelsize"];
  if (((float)diagram_data["yminvalue"]>-LITET)&&
      ((float)diagram_data["yminvalue"]<LITET))
    diagram_data["yminvalue"]=0.0;
  
  if (diagram_data["yminvalue"]<0)
    {
      //placera ut x-axeln.
      //om detta inte funkar s� rita xaxeln l�ngst ner/l�ngst upp och r�kna om diagram_data["ystart"]
      ypos_for_xaxis=((-diagram_data["yminvalue"])*(diagram_data["ystop"]-diagram_data["ystart"]))/
	(diagram_data["ymaxvalue"]-diagram_data["yminvalue"])+diagram_data["ystart"];
      
      int minpos;
      minpos=max(labely, diagram_data["ymaxxnames"])+si*2;
      if (minpos>ypos_for_xaxis)
	{
	  ypos_for_xaxis=minpos;
	  diagram_data["ystart"]=ypos_for_xaxis+
	    diagram_data["yminvalue"]*(diagram_data["ystop"]-ypos_for_xaxis)/
	    (diagram_data["ymaxvalue"]);
	}
      else
	{
	  int maxpos;
	  maxpos=diagram_data["ysize"]-
	    (int)ceil(diagram_data["linewidth"]+si*2)-
	    diagram_data["labelsize"];
	  if (maxpos<ypos_for_xaxis)
	    {
	      ypos_for_xaxis=maxpos;
	      diagram_data["ystop"]=ypos_for_xaxis+
		diagram_data["ymaxvalue"]*(ypos_for_xaxis-diagram_data["ystart"])/
		(0-diagram_data["yminvalue"]);
	    }
	}
    }
  else
    if (diagram_data["yminvalue"]==0.0)
      {
	// s�tt x-axeln l�ngst ner och diagram_data["ystart"] p� samma st�lle.
	diagram_data["ystop"]=diagram_data["ysize"]-
	  (int)ceil(diagram_data["linewidth"]+si)-diagram_data["labelsize"];
	ypos_for_xaxis=max(labely, diagram_data["ymaxxnames"])+si*2;
	diagram_data["ystart"]=ypos_for_xaxis;
      }
    else
      {
	//s�tt x-axeln l�ngst ner och diagram_data["ystart"] en aning h�gre
	diagram_data["ystop"]=diagram_data["ysize"]-
	  (int)ceil(diagram_data["linewidth"]+si)-diagram_data["labelsize"];
	ypos_for_xaxis=max(labely, diagram_data["ymaxxnames"])+si*2;
	diagram_data["ystart"]=ypos_for_xaxis+si*2;
      }
  
  //xpos_for_yaxis=diagram_data["xmaxynames"]+
  // si;

  //Best�m positionen f�r y-axeln
  diagram_data["xstart"]=(int)ceil(diagram_data["linewidth"]);
  diagram_data["xstop"]=diagram_data["xsize"]-
    (int)ceil(diagram_data["linewidth"]+si)-labelx/2;
  if (((float)diagram_data["xminvalue"]>-LITET)&&
      ((float)diagram_data["xminvalue"]<LITET))
    diagram_data["xminvalue"]=0.0;
  
  if (diagram_data["xminvalue"]<0)
    {
      //placera ut y-axeln.
      //om detta inte funkar s� rita yaxeln l�ngst ner/l�ngst upp och r�kna om diagram_data["xstart"]
      xpos_for_yaxis=((-diagram_data["xminvalue"])*(diagram_data["xstop"]-diagram_data["xstart"]))/
	(diagram_data["xmaxvalue"]-diagram_data["xminvalue"])+diagram_data["xstart"];
      
      int minpos;
      minpos=diagram_data["xmaxynames"]+si*2;
      if (minpos>xpos_for_yaxis)
	{
	  xpos_for_yaxis=minpos;
	  diagram_data["xstart"]=xpos_for_yaxis+
	    diagram_data["xminvalue"]*(diagram_data["xstop"]-xpos_for_yaxis)/
	    (diagram_data["ymaxvalue"]);
	}
      else
	{
	  int maxpos;
	  maxpos=diagram_data["xsize"]-
	    (int)ceil(diagram_data["linewidth"]+si*2)-
	    labelx/2;
	  if (maxpos<xpos_for_yaxis)
	    {
	      xpos_for_yaxis=maxpos;
	      diagram_data["xstop"]=xpos_for_yaxis+
		diagram_data["xmaxvalue"]*(xpos_for_yaxis-diagram_data["xstart"])/
		(0-diagram_data["xminvalue"]);
	    }
	}
    }
  else
    if (diagram_data["xminvalue"]==0.0)
      {
	// s�tt y-axeln l�ngst ner och diagram_data["xstart"] p� samma st�lle.
	//write("\nNu blev xminvalue noll!\nxmaxynames:"+diagram_data["xmaxynames"]+"\n");
	
	diagram_data["xstop"]=diagram_data["xsize"]-
	  (int)ceil(diagram_data["linewidth"]+si)-labelx/2;
	xpos_for_yaxis=diagram_data["xmaxynames"]+si*2;
	diagram_data["xstart"]=xpos_for_yaxis;
      }
    else
      {
	//s�tt y-axeln l�ngst ner och diagram_data["xstart"] en aning h�gre
	//write("\nNu blev xminvalue st�rre �n noll!\nxmaxynames:"+diagram_data["xmaxynames"]+"\n");

	diagram_data["xstop"]=diagram_data["xsize"]-
	  (int)ceil(diagram_data["linewidth"]+si)-labelx/2;
	xpos_for_yaxis=diagram_data["xmaxynames"]+si*2;
	diagram_data["xstart"]=xpos_for_yaxis+si*2;
      }
  



  


  //R�kna ut lite skit
  float xstart=(float)diagram_data["xstart"];
  float xmore=(-xstart+diagram_data["xstop"])/
    (diagram_data["xmaxvalue"]-diagram_data["xminvalue"]);
  float ystart=(float)diagram_data["ystart"];
  float ymore=(-ystart+diagram_data["ystop"])/
    (diagram_data["ymaxvalue"]-diagram_data["yminvalue"]);
  
  
  draw_grind(diagram_data, xpos_for_yaxis, ypos_for_xaxis, 
	     xmore, ymore, xstart, ystart, (float) si);
  


  //Rita ut bars datan
  int farg=0;
  //write("xstart:"+diagram_data["xstart"]+"\nystart"+diagram_data["ystart"]+"\n");
  //write("xstop:"+diagram_data["xstop"]+"\nystop"+diagram_data["ystop"]+"\n");

  if (diagram_data["type"]=="sumbars")
    {
      int s=sizeof(diagram_data["data"][0]);
      float barw=diagram_data["xspace"]*xmore/3.0;
      for(int i=0; i<s; i++)
	{
	  int j=0;
	  float x,y;
	  x=xstart+(diagram_data["xspace"]/2.0+diagram_data["xspace"]*i)*
	    xmore;
	  
	  y=-(-diagram_data["yminvalue"])*ymore+
	    diagram_data["ysize"]-ystart;	 
	  float start=y;

	  foreach(column(diagram_data["data"], i), float d)
	    {
	      y-=d*ymore;
	      
	      
	      barsdiagram->setcolor(@(diagram_data["datacolors"][j++]));
	      
	      barsdiagram->polygone(
				    ({x-barw+0.01, y //FIXME
				      , x+barw+0.01, y, //FIXME
				      x+barw, start
				      , x-barw, start
				    }));  
	      barsdiagram->setcolor(0,0,0);
	      draw(barsdiagram, 0.5, 
		   ({
		     x-barw, start,
		     x-barw+0.01, y //FIXME
		     , x+barw+0.01, y, //FIXME
		     x+barw, start

		   })
		   );

	      start=y;
	    }
	}
    }
  else
  if (diagram_data["subtype"]=="line")
    if (diagram_data["drawtype"]=="linear")
      foreach(diagram_data["data"], array(float) d)
	{
	  array(float) l=allocate(sizeof(d)*2);
	  for(int i=0; i<sizeof(d); i++)
	    {
	      l[i*2]=xstart+(diagram_data["xspace"]/2.0+diagram_data["xspace"]*i)*
		xmore;
	      l[i*2+1]=-(d[i]-diagram_data["yminvalue"])*ymore+
		diagram_data["ysize"]-ystart;	  
	    }
	  
	  barsdiagram->setcolor(@(diagram_data["datacolors"][farg++]));
	  draw(barsdiagram, diagram_data["linewidth"],l);
	}
    else
      throw( ({"\""+diagram_data["drawtype"]+"\" is an unknown bars-diagram drawtype!\n",
	       backtrace()}));
  else
    if (diagram_data["subtype"]=="box")
      if (diagram_data["drawtype"]=="2D")
	{
	  int s=sizeof(diagram_data["data"]);
	  float barw=diagram_data["xspace"]*xmore/1.5;
	  float dnr=-barw/2.0+ barw/s/2.0;
	  barw/=s;
	  barw/=2.0;
	  farg=-1;
	  foreach(diagram_data["data"], array(float) d)
	    {
	      farg++;

	      for(int i=0; i<sizeof(d); i++)
		{
		  float x,y;
		  x=xstart+(diagram_data["xspace"]/2.0+diagram_data["xspace"]*i)*
		    xmore;
		  y=-(d[i]-diagram_data["yminvalue"])*ymore+
		    diagram_data["ysize"]-ystart;	 
		  
		  // if (y>diagram_data["ysize"]-ypos_for_xaxis-diagram_data["linewidth"]) 
		  // y=diagram_data["ysize"]-ypos_for_xaxis-diagram_data["linewidth"];

		  barsdiagram->setcolor(@(diagram_data["datacolors"][farg]));
  
		  barsdiagram->polygone(
					({x-barw+0.01+dnr, y //FIXME
					  , x+barw+0.01+dnr, y, //FIXME
					  x+barw+dnr, diagram_data["ysize"]-ypos_for_xaxis
					  , x-barw+dnr,diagram_data["ysize"]- ypos_for_xaxis
					})); 
		  barsdiagram->setcolor(0,0,0);		  
		  draw(barsdiagram, 0.5, 
		       ({x-barw+0.01+dnr, y //FIXME
			 , x+barw+0.01+dnr, y, //FIXME
			 x+barw+dnr, diagram_data["ysize"]-ypos_for_xaxis
			 , x-barw+dnr,diagram_data["ysize"]- ypos_for_xaxis,
			 x-barw+0.01+dnr, y //FIXME
		       })); 
		}
	      dnr+=barw*2.0;
	    }   
	}
      else
	throw( ({"\""+diagram_data["drawtype"]+"\" is an unknown bars-diagram drawtype!\n",
		 backtrace()}));
    else
      throw( ({"\""+diagram_data["subtype"]+"\" is an unknown bars-diagram subtype!\n",
	       backtrace()}));


  
  //Rita ut axlarna
  barsdiagram->setcolor(@(diagram_data["axcolor"]));
  
  //write((string)diagram_data["xminvalue"]+"\n"+(string)diagram_data["xmaxvalue"]+"\n");

  
  //Rita xaxeln
  if ((diagram_data["xminvalue"]<=LITET)&&
      (diagram_data["xmaxvalue"]>=-LITET))
    barsdiagram->
      polygone(make_polygon_from_line(diagram_data["linewidth"], 
				      ({
					diagram_data["linewidth"],
					diagram_data["ysize"]- ypos_for_xaxis,
					diagram_data["xsize"]-
					diagram_data["linewidth"]-labelx/2, 
					diagram_data["ysize"]-ypos_for_xaxis
				      }), 
				      1, 1)[0]);
  else
    if (diagram_data["xmaxvalue"]<-LITET)
      {
	//write("xpos_for_yaxis"+xpos_for_yaxis+"\n");

	//diagram_data["xstop"]-=(int)ceil(4.0/3.0*(float)si);
	barsdiagram->
	  polygone(make_polygon_from_line(diagram_data["linewidth"], 
					  ({
					    diagram_data["linewidth"],
					    diagram_data["ysize"]- ypos_for_xaxis,
					    
					    xpos_for_yaxis-4.0/3.0*si, 
					    diagram_data["ysize"]-ypos_for_xaxis,
					    
					    xpos_for_yaxis-si, 
					    diagram_data["ysize"]-ypos_for_xaxis-
					    si/2.0,
					    xpos_for_yaxis-si/1.5, 
					    diagram_data["ysize"]-ypos_for_xaxis+
					    si/2.0,
					    
					    xpos_for_yaxis-si/3.0, 
					    diagram_data["ysize"]-ypos_for_xaxis,

					    diagram_data["xsize"]-diagram_data["linewidth"]-labelx/2, 
					    diagram_data["ysize"]-ypos_for_xaxis

					  }), 
					  1, 1)[0]);
      }
    else
      if (diagram_data["xminvalue"]>LITET)
	{
	  //diagram_data["xstart"]+=(int)ceil(4.0/3.0*(float)si);
	  barsdiagram->
	    polygone(make_polygon_from_line(diagram_data["linewidth"], 
					    ({
					      diagram_data["linewidth"],
					      diagram_data["ysize"]- ypos_for_xaxis,
					      
					      xpos_for_yaxis+si/3.0, 
					      diagram_data["ysize"]-ypos_for_xaxis,
					      
					      xpos_for_yaxis+si/1.5, 
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si/2.0,
					      xpos_for_yaxis+si, 
					      diagram_data["ysize"]-ypos_for_xaxis+
					      si/2.0,
					      
					      xpos_for_yaxis+4.0/3.0*si, 
					      diagram_data["ysize"]-ypos_for_xaxis,
					      
					      diagram_data["xsize"]-diagram_data["linewidth"]-labelx/2, 
					      diagram_data["ysize"]-ypos_for_xaxis
					      
					    }), 
					    1, 1)[0]);

	}
  
  //Rita pilen p� xaxeln
  /*  barsdiagram->
    polygone(make_polygon_from_line(diagram_data["linewidth"], 
				    ({
				      diagram_data["xsize"]-
				      diagram_data["linewidth"]-
				      (float)si/2.0-labelx/2, 
				      diagram_data["ysize"]-ypos_for_xaxis-
				      (float)si/2.0,
				      diagram_data["xsize"]-
				      diagram_data["linewidth"]-labelx/2, 
				      diagram_data["ysize"]-ypos_for_xaxis,
				      diagram_data["xsize"]-
				      diagram_data["linewidth"]-
				      (float)si/2.0-labelx/2, 
				      diagram_data["ysize"]-ypos_for_xaxis+
				      (float)si/2.0
				    }), 
				    1, 1)[0]);*/

  //Rita yaxeln
  if ((diagram_data["yminvalue"]<=LITET)&&
      (diagram_data["ymaxvalue"]>=-LITET))
      barsdiagram->
	polygone(make_polygon_from_line(diagram_data["linewidth"], 
					({
					  xpos_for_yaxis,
					  diagram_data["ysize"]-diagram_data["linewidth"],
					  
					  xpos_for_yaxis,
					  diagram_data["linewidth"]+
					  diagram_data["labelsize"]
					}), 
					1, 1)[0]);
  else
    if (diagram_data["ymaxvalue"]<-LITET)
      {
	barsdiagram->
	  polygone(make_polygon_from_line(diagram_data["linewidth"], 
					  ({
					    xpos_for_yaxis,
					    diagram_data["ysize"]-diagram_data["linewidth"],

					    xpos_for_yaxis,
					    diagram_data["ysize"]-ypos_for_xaxis+
					    si*4.0/3.0,

					    xpos_for_yaxis-si/2.0,
					    diagram_data["ysize"]-ypos_for_xaxis+
					    si,
					    
					    xpos_for_yaxis+si/2.0,
					    diagram_data["ysize"]-ypos_for_xaxis+
					    si/1.5,
					    
					    xpos_for_yaxis,
					    diagram_data["ysize"]-ypos_for_xaxis+
					    si/3.0,
					    
					    xpos_for_yaxis,
					    diagram_data["linewidth"]+
					    diagram_data["labelsize"]
					  }), 
					  1, 1)[0]);
      }
    else
      if (diagram_data["yminvalue"]>LITET)
	{/*
	  write("\n\n"+sprintf("%O",make_polygon_from_line(diagram_data["linewidth"], 
					    ({
					      xpos_for_yaxis,
					      diagram_data["ysize"]-diagram_data["linewidth"],

					      xpos_for_yaxis,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si/3.0,
					      
					      xpos_for_yaxis-si/2.0,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si/1.5,
					    
					      xpos_for_yaxis+si/2.0,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si,
					      
					      xpos_for_yaxis,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si*4.0/3.0,
					    
					      xpos_for_yaxis+0.0001, //FIXME!
					      diagram_data["linewidth"]+
					      diagram_data["labelsize"]
					      
					    }), 
					    1, 1)[0])+
					    "\n\n");*/
	  barsdiagram->
	    polygone(make_polygon_from_line(diagram_data["linewidth"], 
					    ({
					      xpos_for_yaxis,
					      diagram_data["ysize"]-diagram_data["linewidth"],

					      xpos_for_yaxis,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si/3.0,
					      
					      xpos_for_yaxis-si/2.0,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si/1.5,
					    
					      xpos_for_yaxis+si/2.0,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si,
					      
					      xpos_for_yaxis,
					      diagram_data["ysize"]-ypos_for_xaxis-
					      si*4.0/3.0,
					    
					      xpos_for_yaxis+0.01, //FIXME!
					      diagram_data["linewidth"]+
					      diagram_data["labelsize"]
					      
					    }), 
					    1, 1)[0]);

	}
    
  //Rita pilen
  /* barsdiagram->
    polygone(make_polygon_from_line(diagram_data["linewidth"], 
				    ({
				      xpos_for_yaxis-
				      (float)si/2.0,
				      diagram_data["linewidth"]+
				      (float)si/2.0+
					  diagram_data["labelsize"],
				      
				      xpos_for_yaxis,
				      diagram_data["linewidth"]+
					  diagram_data["labelsize"],
	
				      xpos_for_yaxis+
				      (float)si/2.0,
				      diagram_data["linewidth"]+
				      (float)si/2.0+
					  diagram_data["labelsize"]
				    }), 
				    1, 1)[0]);
  */
  barsdiagram->
    polygone(
	     ({
	       xpos_for_yaxis-
	       (float)si/4.0,
	       diagram_data["linewidth"]/2.0+
	       (float)si/2.0+
	       diagram_data["labelsize"],
				      
	       xpos_for_yaxis,
	       diagram_data["linewidth"]/2.0+
	       diagram_data["labelsize"],
	
	       xpos_for_yaxis+
	       (float)si/4.0,
	       diagram_data["linewidth"]/2.0+
	       (float)si/2.0+
	       diagram_data["labelsize"]
	     })); 
  



  //Placera ut texten p� X-axeln
  int s=sizeof(diagram_data["xnamesimg"]);
  for(int i=0; i<s; i++)
    {
      barsdiagram->paste_alpha_color(diagram_data["xnamesimg"][i], 
			       @(diagram_data["textcolor"]), 
			       (int)floor((diagram_data["values_for_xnames"][i]-
					   diagram_data["xminvalue"])
					  *xmore+xstart
					  -
					  diagram_data["xnamesimg"][i]->xsize()/2), 
			       (int)floor(diagram_data["ysize"]-ypos_for_xaxis+
					  si/2.0));
      /*   barsdiagram->
	polygone(make_polygon_from_line(diagram_data["linewidth"], 
					({
					  ((diagram_data["values_for_xnames"][i]-
					    diagram_data["xminvalue"])
					   *xmore+xstart),
					  diagram_data["ysize"]-ypos_for_xaxis+
					   si/4,
					  ((diagram_data["values_for_xnames"][i]-
					    diagram_data["xminvalue"])
					   *xmore+xstart),
					  diagram_data["ysize"]-ypos_for_xaxis-
					   si/4
					}), 
					1, 1)[0]);*/
    }

  //Placera ut texten p� Y-axeln
  s=sizeof(diagram_data["ynamesimg"]);
  for(int i=0; i<s; i++)
    {
      //write("\nYmaXnames:"+diagram_data["ymaxynames"]+"\n");
      barsdiagram->paste_alpha_color(diagram_data["ynamesimg"][i], 
			       @(diagram_data["textcolor"]), 
			       (int)floor(xpos_for_yaxis-
					  si/2.0-diagram_data["linewidth"]*2-
					  diagram_data["ynamesimg"][i]->xsize()),
			       (int)floor(-(diagram_data["values_for_ynames"][i]-
					    diagram_data["yminvalue"])
					  *ymore+diagram_data["ysize"]-ystart
					  -
					  diagram_data["ymaxynames"]/2));
      barsdiagram->
	polygone(make_polygon_from_line(diagram_data["linewidth"], 
					({
					  xpos_for_yaxis-
					   si/4,
					  (-(diagram_data["values_for_ynames"][i]-
					     diagram_data["yminvalue"])
					   *ymore+diagram_data["ysize"]-ystart),

					  xpos_for_yaxis+
					   si/4,
					  (-(diagram_data["values_for_ynames"][i]-
					     diagram_data["yminvalue"])
					   *ymore+diagram_data["ysize"]-ystart)
					}), 
					1, 1)[0]);
    }


  //S�tt ut labels ({xstorhet, ystorhet, xenhet, yenhet})
  if (diagram_data["labelsize"])
    {
      barsdiagram->paste_alpha_color(labelimg, 
			       @(diagram_data["labelcolor"]), 
			       diagram_data["xsize"]-labelx-(int)ceil((float)diagram_data["linewidth"]),
			       diagram_data["ysize"]-(int)ceil((float)(ypos_for_xaxis-si)));
      
      string label;
      int x;
      int y;

      if (diagram_data["labels"][3] && sizeof(diagram_data["labels"][3]))
	label=diagram_data["labels"][1]+" ["+diagram_data["labels"][3]+"]"; //Ystorhet
      else
	label=diagram_data["labels"][1];
      if ((label!="")&&(label!=0))
	labelimg=get_font("avant_garde", 32, 0, 0, "left",0,0)->
	  write(label)
#ifndef ROXEN
->scale(0,diagram_data["labelsize"])
#endif
;
      else
	labelimg=image(diagram_data["labelsize"],diagram_data["labelsize"]);
      
      
	//if (labelimg->xsize()> barsdiagram->xsize())
	//labelimg->scale(barsdiagram->xsize(),labelimg->ysize());
      
      x=max(0,((int)floor((float)xpos_for_yaxis)-labelimg->xsize()/2));
      x=min(x, barsdiagram->xsize()-labelimg->xsize());
      
      y=0; 

      
      if (label && sizeof(label))
	barsdiagram->paste_alpha_color(labelimg, 
				 @(diagram_data["labelcolor"]), 
				 x,
				 0);
      
      

    }


  diagram_data["ysize"]-=diagram_data["legend_size"];
  diagram_data["image"]=barsdiagram;
  return diagram_data;



}

#ifndef ROXEN
int main(int argc, string *argv)
{
  //write("\nRitar axlarna. Filen sparad som test.ppm\n");

  mapping(string:mixed) diagram_data;
  diagram_data=(["type":"sumbars",
		 "textcolor":({0,0,0}),
		 "subtype":"norm",
		 "orient":"vert",
		 "data": 
		 ({ ({91.2, 102.3, 94.01, 100.0, 94.3, 102.0 }),
		     ({91.2, 101.3, 91.5, 101.7,  41.0, 101.5}),
		    ({91.2, 103.3, 41.5, 100.1, 94.3, 95.2 }),
		    ({93.2, 13.3, 93.5, 103.7, 94.3, 41.2 }) }),
		 "fontsize":32,
		 "axcolor":({0,0,0}),
		 "bgcolor":0,//({255,255,255}),
		 "labelcolor":({0,0,0}),
		 "datacolors":({({0,255,0}),({255,255,0}), ({0,255,255}), ({255,0,255}) }),
		 "linewidth":2.2,
		 "xsize":400,
		 "ysize":200,
		 "xnames":({"jan", "feb", "mar", "apr", "maj", "jun"}),
		 "fontsize":16,
		 "labels":0,//({"xstor", "ystor", "xenhet", "yenhet"}),
		 "legendfontsize":12,
		 "legend_texts":({"streck 1", "streck 2", "foo", "bar gazonk foobar illalutta!" }),
		 "labelsize":12,
		 "xminvalue":0.1,
		 "yminvalue":0,
		 "horgrind": 1,
		 "grindwidth": 0.5
  ]);

  object o=Stdio.File();
  o->open("test.ppm", "wtc");
  o->write(create_bars(diagram_data)["image"]->toppm());
  o->close();

};
#endif
