 
*dk,nearestpoint0
      subroutine nearestpoint0(xq,yq,zq,xs,ys,zs,
     &   linkt,sbox,eps,mtri,mtfound,itfound,ierr)
c
c #####################################################################
c
c     purpose -
c
c     NEARESTPOINT0 uses the k-D tree structure
c     generated by KDTREE0 to accelerate finding the nearest point
c     to the given query point (XQ,YQ,ZQ).
c     We actually return the nearest point, as well as other
c     points that are NEARLY the nearest point within a distance
c     of EPS.  We do not attempt to order this set in any way.
c
c     input arguments -
c
c         xq,yq,zq  -    spatial coordinates of query point.
c         xs,ys,zs  -    spatial coordinates of PREVIOUS nearest
c                        point obtained in the sequence of nearest
c                        point queries.  If there is no previous
c                        query, or the coordinates are unknown, they
c                        should be set to ``infinity''.  (This info
c                        can accelerate the search when query points
c                        are spatially correlated.)
c         linkt,sbox -   k-D tree arrays.
c         eps  -         epsilon for length comparisons.  If negative,
c                        we redefine it to be DEFAULT_EPSILON_FRACTION
c                        (currently 1.e-10) multiplied by the diameter
c                        of the smallest box containing all the points
c                        in the tree.
c         distpossleaf   a ``work'' array of length ``mtri'' (no. of
c                        points in k-D tree)
c
c     output arguments -
c         mtfound -      no. of leaves (triangles) returned
c         itfound -      array of triangles returned
c         outside -      logical set to true if the query point
c                        is outside (by more than EPS) the smallest
c                        box containing all the points in the tree.
c                        This is disabled
c         ierr -         error return.
c
c     change history -
c
C         $Log: nearestpoint0.f,v $
C         Revision 2.00  2007/11/05 19:46:02  spchu
C         Import to CVS
C
CPVCS    
CPVCS       Rev 1.5   Wed Feb 04 09:35:44 1998   kmb
CPVCS    No change.
CPVCS    
CPVCS       Rev 1.4   Fri Oct 17 12:56:02 1997   dcg
CPVCS    fix bad declarations (pointer and integer)
CPVCS
CPVCS       Rev 1.3   Fri Jun 20 15:59:44 1997   dcg
CPVCS    changes needed by upscale command
 
      implicit none
      include 'consts.h'
 
      integer mtri,length,icscode
      integer itfound(1000000),mtfound,linkt(2*mtri),ierr
      real*8 xq,yq,zq,eps,
     &   distpossleaf(mtri),xs,ys,zs,sbox(2,3,mtri)
      logical outside
 
      integer istack(100)
      real*8 distposs(100),distconf(100)
 
      integer i,k,node,ind,iord(0:1),itop,nleaves
      real*8 dmin,distpossch(0:1),distconfch(0:1),dposs,dconf
 
      real*8 default_epsilon_fraction
      parameter (default_epsilon_fraction=1.e-10)
 
      character*32 isubname
      pointer (ipdistpossleaf, distpossleaf)
 
      isubname='nearestpoint0'
      length=mtri
      call mmgetblk('distpossleaf',isubname,ipdistpossleaf,
     $     length,2,icscode)
 
c.... Define EPS, if negative.
 
      if (eps.lt.zero) then
         eps=default_epsilon_fraction*
     &      sqrt((sbox(2,1,1)-sbox(1,1,1))**2+
     &      (sbox(2,2,1)-sbox(1,2,1))**2+
     &      (sbox(2,3,1)-sbox(1,3,1))**2)
      endif
 
c.... Define OUTSIDE.
 
c     if (xq.lt.sbox(1,1,1)-eps.or.xq.gt.sbox(2,1,1)+eps.or.
c    &   yq.lt.sbox(1,2,1)-eps.or.yq.gt.sbox(2,2,1)+eps.or.
c    &   zq.lt.sbox(1,3,1)-eps.or.zq.gt.sbox(2,3,1)+eps) then
c        outside=.true.
c     else
c        outside=.false.
c     endif
 
c.... If the root node is a leaf, return it.
 
      if (linkt(1).lt.0) then
         mtfound=1
         itfound(1)=-linkt(1)
         goto 9999
      endif
 
      nleaves=0
 
c.... Initialize the minimum distance to be
c.... the distance from the query point to the point most
c.... distant on the bounding box for the whole geometry.
c.... (DMIN is always a guaranteed (i.e., pessimistic)
c.... estimate.)
 
      dmin=sqrt(max((xq-sbox(1,1,1))**2,(xq-sbox(2,1,1))**2)+
     &   max((yq-sbox(1,2,1))**2,(yq-sbox(2,2,1))**2)+
     &   max((zq-sbox(1,3,1))**2,(zq-sbox(2,3,1))**2))
 
c.... Since (xs,ys,zs) is a valid point, we can
c.... decrease DMIN if this is closer.  This can significantly
c.... speed up the search if (xs,ys,zs) is NEARLY the closest
c.... point.  This is because a low value of DMIN can prevent
c.... the algorithm from having to search most of k-D tree.
c.... (Of course, if DMIN were initialized to an unjustifiably
c.... small distance, the algorithm would fail.)
 
      dmin=min(dmin,sqrt((xq-xs)**2+(yq-ys)**2+(zq-zs)**2))
 
c.... Place root node on stack.
 
      itop=1
      istack(itop)=1
      distposs(itop)=0.
      distconf(itop)=dmin
 
c.... (Partially) traverse k-D tree using a stack until done.
 
      do while (itop.gt.0)
 
c.... Pop node off of top of stack.  DPOSS contains the minimum
c.... distance from the bounding box of the node to the query point;
c.... DCONF contains the maximum.
 
         node=istack(itop)
         dposs=distposs(itop)
         dconf=distconf(itop)
         itop=itop-1
 
c.... We only look at this node if the minimum ``optimistic'' distance
c.... for the node is less than the known ``pessimistic'' distance
c.... to the nearest point.
c.... EPS insures that we are conservative and avoid discarding a
c.... valid node because of rounding error problems.
 
         if (dposs.le.dmin+eps) then
            dmin=min(dmin,dconf)
            ind=linkt(node)
 
c.... For each child of the node, work out pessimistic and
c.... optimistic distances, and place them in DISTCONFCH and
c.... DISTPOSSCH respectively.  Reduce the global pessimistic
c.... distance DMIN if appropriate.
 
            do k=0,1
               distconfch(k)=sqrt(
     &            max((xq-sbox(1,1,ind+k))**2,
     &            (xq-sbox(2,1,ind+k))**2)+
     &            max((yq-sbox(1,2,ind+k))**2,
     &            (yq-sbox(2,2,ind+k))**2)+
     &            max((zq-sbox(1,3,ind+k))**2,
     &            (zq-sbox(2,3,ind+k))**2) )
               distpossch(k)=sqrt((max(zero,
     &            sbox(1,1,ind+k)-xq,
     &            xq-sbox(2,1,ind+k)))**2+
     &            (max(zero,sbox(1,2,ind+k)-yq,
     &            yq-sbox(2,2,ind+k)))**2+
     &            (max(zero,sbox(1,3,ind+k)-zq,
     &            zq-sbox(2,3,ind+k)))**2)
               dmin=min(dmin,distconfch(k))
            enddo
 
c.... Order the children so that the child with the
c.... smaller optimistic distance will be put on top of
c.... the other child if they are both put on the stack.
 
            if (distpossch(0).lt.distpossch(1)) then
               iord(0)=0
               iord(1)=1
            else
               iord(0)=1
               iord(1)=0
            endif
 
c.... Loop thru the children and check if they are still
c.... feasible.  Ignore nonfeasible children whose optimistic
c.... distance is greater than DMIN+EPS.
 
            do k=1,0,-1
               if (distpossch(iord(k)).le.dmin+eps) then
 
c.... If the child is a leaf, add it to output list, and
c.... add its optimistic distance to the leaf array containing
c.... these distances.  If the child is not a leaf, put it
c.... on the stack.
 
                  if (linkt(ind+iord(k)).lt.0) then
                     nleaves=nleaves+1
                     itfound(nleaves)=ind+iord(k)
                     distpossleaf(nleaves)=distpossch(iord(k))
                  else
                     itop=itop+1
                     istack(itop)=ind+iord(k)
                     distposs(itop)=distpossch(iord(k))
                     distconf(itop)=distconfch(iord(k))
                  endif
               endif
            enddo
         endif
      enddo
 
c.... Compress the list of recovered leaves by accepting
c.... any leaves whose optimistic distance is less or equal to
c.... DMIN + EPS.
c.... (This is necessary, since DMIN may have been reduced since
c.... the leaves were originally added to the list.)  Convert
c.... the leaf addresses to point indices at the same time.
 
      mtfound=0
      do i=1,nleaves
         if (distpossleaf(i).le.dmin+eps) then
            mtfound=mtfound+1
            itfound(mtfound)=-linkt(itfound(i))
         endif
      enddo
 
 9999 continue
 
c     Release memory block
      call mmrelblk('distpossleaf' ,isubname,ipdistpossleaf,icscode)
 
      return
      end