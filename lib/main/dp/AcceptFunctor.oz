%%%
%%% Authors:
%%%   Erik Klintskog (erik@sics.se)
%%%   Anna Neiderud (annan@sics.se)
%%%
%%% Copyright:
%%%
%%% Last change:
%%%   $Date$ by $Author$
%%%   $Revision$
%%%
%%% This file is part of Mozart, an implementation
%%% of Oz 3
%%%    http://www.mozart-oz.org
%%%
%%% See the file "LICENSE" or
%%%    http://www.mozart-oz.org/LICENSE.html
%%% for information on usage and redistribution
%%% of this file, and for a DISCLAIMER OF ALL
%%% WARRANTIES.
%%%

%\define DBG
functor
export
   Accept
import
   OS
\ifdef DBG
   System
\endif
   DPMisc
define
   class ResourceHandler
      prop
         locking
      attr
         r
         q
      meth init(I)
         r<-I
         q<-nil
      end
      meth getResource
         lock W in
            if @r>0 then
               r<-@r-1
               W=unit
            else
               q<-{Append @q [W]}
            end
            {Wait W}
         end
      end
      meth returnResource
         lock
            if @q==nil then
               r<-@r+1
            else
               Q1|QR=@q
            in
               @r=0 % Check
               q<-QR
               Q1=unit
            end
         end
      end
   end

   MaxRead = 1000

   FDHandler = {New ResourceHandler init(5)}
   fun{BindSocket FD PortNum}
      try
         {OS.bind FD PortNum}
         PortNum
      catch _ then
         {BindSocket FD PortNum + 1}
      end
   end

   proc{AcceptSelect FD}
      NewFD in
      try
\ifdef DBG
         {System.showInfo 'AcceptedSelect on '#FD}
\endif
         {FDHandler getResource}
\ifdef DBG
         {System.showInfo 'Got resource'}
\endif
         {OS.acceptSelect FD}
\ifdef DBG
         {System.showInfo 'After acceptSelect '#FD}
\endif
         {OS.acceptNonblocking FD _ _ NewFD} %InAddress InIPPort NewFD}
\ifdef DBG
         {System.showInfo 'Accepted channel (old '#FD#' new '#NewFD#')'}
\endif
         thread
            {AcceptProc NewFD}
            {FDHandler returnResource}
         end
\ifdef DBG
      % If there is an exception here we can't do much but return the
      % resources and close the socket. The most likely exception is
      % a EPIPE on the new FD.
      catch X then
         {System.show exception_AcceptSelect(X)}
\else
      catch _ then
         skip
\endif
         {FDHandler returnResource}
         {OS.close NewFD}
      end
      {AcceptSelect FD}
   end

   proc{Accept}
%      InAddress InIPPort
      FD
      PortNum
   in
      /* Create socket */
      FD={OS.socket 'PF_INET' 'SOCK_STREAM' "tcp"}
      PortNum = {BindSocket FD 9000}
      {OS.listen FD 5}
      {DPMisc.setListenPort PortNum {OS.uName}.nodename}
\ifdef DBG
      {System.showInfo 'Listening on port '#PortNum#' using fd '#FD}
\endif
      thread {AcceptSelect FD} end
   end

   proc{AcceptProc FD}
      Read InString
   in
      try
         {OS.readSelect FD}
         {OS.read FD MaxRead ?InString nil ?Read}

         if Read>0 then
            case InString of "tcp" then
               Grant = {DPMisc.getConnGrant accept tcp false}
            in
               case Grant of grant(...) then
\ifdef DBG
                  {System.showInfo accepted}
\endif
                  _={OS.write FD "ok"}
                  {DPMisc.handover accept Grant settings(fd:FD)}
               else % could be busy or no tcp, wait for anoter try
\ifdef DBG
                  {System.showInfo busy}
\endif
                  _={OS.write FD "no"}
                  {AcceptProc FD}
               end
            [] "give_up" then
               {OS.close FD}
            else
               {OS.close FD}
            end
         else
            % AN! can this happen or will there allways be an exception?
            {OS.close FD}
         end
      catch X then
         case X of system(os(_ _ _ "Try again") ...) then % EAGAIN => try again
            {AcceptProc FD}
         else % Other fault conditions AN! should some others be treated?
            {OS.close FD}
         end
      end
   end
end
