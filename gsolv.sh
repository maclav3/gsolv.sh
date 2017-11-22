#!/bin/bash

# Quite heavily based upon Sander Pronk's 
# "Hands-on tutorial: Solvation free energy of ethanol"
# http://www.gromacs.org/Documentation/Tutorials/Free_energy_of_solvation_tutorial

if [ $#  -lt 4 ]; then
    echo "Usage: $0 topol.top conf.gro dirname molecule_name maxwarn."
    echo ""
    echo "Performs flexible EM, regular EM, equilibriation run, then FEP from no vdw and no coulomb to full vdw/coulomb parameters."
    echo "Prepares lambda_\$i directories with given mdp file, topology, and configuration"
    echo "Replaces \$LAMBDA\$ in FEP mdp file with current lambda values"
    echo "Replaces \$ALL_LAMBDAS\$ in mdp file with list of current lambda values"
    echo "molecule_name must be given in accordance with the topology file."
    echo "maxwarn may be used to increase maxwarn in grompp calls (e.g. when modifying atomtypes in topology)"
    exit 1
fi

DIRNAME=$3 #The directory that we will be working in
mkdir -p $DIRNAME
cd $DIRNAME

EM_FLEXIBLE_MDP="mdp/em_flexible.mdp" #MDP for flexible EM
EM_MDP="mdp/em.mdp" #MDP for regular EM
EQUI_MDP="mdp/equi.mdp" #MDP for the equilibriation run
FEP_RUN_MDP="mdp/run.mdp" #MDP for the FEP run

TOPOLOGY_FILE=$1 #Topology, including water (solvation free energy)
CONFIGURATION_FILE=$2 #Configuration, incl. water
MOLECULE=$4 #Molecule name, as defined in the topology (for couple-moltype in FEP runs)

if test -z "$5"
then
MAXWARN=0
#ideally, MAXWARN should be equal to the number of altered atomtypes
#in the topology (to deal with grompp's warnings about overriding atom types)
exit 1
else
MAXWARN=$5
fi

find . -name "\#*\#" -delete #remove temp files, if any

# adjust if needed
lambdas=( 0.0000 0.0250 0.0500 0.0750 0.1000 0.1250 0.1500 0.1750 0.2000 0.2250 0.2500 0.2750 0.3000 0.3250 0.3500 0.3750 0.4000 0.4250 0.4500 0.4750 0.5000 0.5250 0.5500 0.5750 0.6000 0.6250 0.6500 0.6750 0.7000 0.7250 0.7500 0.7750 0.8000 0.8250 0.8500 0.8750 0.9000 0.9250 0.9500 0.9750 1.0000 )
all=${lambdas[@]}

#flexible EM
echo "Performing flexible EM"
rm -rf em-flex
mkdir em-flex
gmx grompp -maxwarn $MAXWARN -f ../$EM_FLEXIBLE_MDP -p ../$TOPOLOGY_FILE -c ../$CONFIGURATION_FILE -o em-flex/em-flex.tpr &> em-flex/grompp.out
cd em-flex
gmx mdrun -deffnm em-flex &> md.out
cd ..

#regular EM
echo "Performing regular EM"
rm -rf em
mkdir em
gmx grompp -maxwarn $MAXWARN -f ../$EM_MDP -p ../$TOPOLOGY_FILE -c em-flex/em-flex.gro -o em/em.tpr &> em/grompp.out
cd em
gmx mdrun -deffnm em &> md.out
cd ..

#equilibriation
echo "Performing equilibriation"
rm -rf equi
mkdir equi
gmx grompp -maxwarn $MAXWARN -f ../$EQUI_MDP -p ../$TOPOLOGY_FILE -c em/em.gro -o equi/equi.tpr &> equi/grompp.out
cd equi
gmx mdrun -deffnm equi &> md.out
cd ..

n=0
maxn=${#lambdas[@]}

echo "Making directories, populating them and running MD" 
for i in "${lambdas[@]}"; do
    newdir="lambda_$i"
    echo "[$((100*n/maxn)) %] $newdir"
    n=$[n+1]
    mkdir -p $newdir
    # now do the substitution
    sed "s/\\\$LAMBDA\\\$/${i}/" ../$FEP_RUN_MDP | sed "s/\\\$ALL_LAMBDAS\\\$/${all}/" | sed "s/\\\$MOLECULE\\\$/$4/"> $newdir/grompp.mdp
    
    #and prepare the run
    cd $newdir
    gmx grompp -maxwarn $MAXWARN -f grompp.mdp -c ../equi/equi.gro -p ../../$TOPOLOGY_FILE -o fep_run.tpr &> grompp.out
    #run the FEP simulation - alter this if computing FEP runs elsewhere (e.g. PBS)
    gmx mdrun -deffnm fep_run &> fep.out 

    find . -name "\#*\#" -delete #remove temp files, if any
    cd ..
done

#perform BAR calculations
gmx bar -f lambda*/fep_run.xvg -o -oi &> g_bar.log 
#The last line of g_bar log is the DG_solv in kJ/mol.

