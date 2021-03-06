#
## $Id: Global.pm,v 8.3 2012/09/21 04:56:33 keiths Exp $
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#  
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#  
#  This file is part of Network Management Information System (“NMIS”).
#  
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).  
#  If not, see <http://www.gnu.org/licenses/>
#  
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com 
#  
#  User group details:
#  http://support.opmantek.com/users/
#  
# *****************************************************************************

package NMIS::Global;

use strict;
use lib "../../lib";
use Exporter;

use vars qw($C @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);

@ISA = qw/ Exporter /;

@EXPORT = qw/ $C /;

use NMIS::Config ();
$C = NMIS::Config->new(  );

# our $READONLY;
# *READONLY = \42;

1;




                                                                                                                                                                                                                                                        
