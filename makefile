# http://www.bevanlab.biochem.vt.edu/Pages/Personal/justin/gmx-tutorials/lysozyme/index.html
GMX=gmx -nobackup
VMD=/opt/apps/VMD/vmd-1.9.3-install/vmd-1.9.3-install/vmd_LINUXAMD64
view:
	vglrun $(VMD) 1AKI.pdb
	echo  (also load trajectory file: md_0_1.trr) extensions -> vis -> movie maker
	vglrun $(VMD) md_0_1.gro 

ifeq ($(TACC_SYSTEM),stampede2)
        MDRUN = ibrun mdrun_mpi  -maxh 48
        FORCEFIELDID=27
else
        MDRUN = $(GMX) mdrun -nb gpu
        FORCEFIELDID=14
endif


# keep tmp files
.SECONDARY: 
PDBFILES=1AKI 2ihr 
CONCENTRATION=.025 .050 .100 .200 .400 .800
TEMPERATURE=300 310 316 330 350
setup: $(foreach idconc,$(CONCENTRATION),$(addsuffix  /$(idconc)/newbox.gro,$(PDBFILES)))

# debug
echo : 
	@echo $(foreach idtemp,$(TEMPERATURE),$(foreach idconc,$(CONCENTRATION),$(addsuffix  $(idtemp)/$(idconc)/newbox.gro,$(PDBFILES))))

# cleanup
clean:
	rm *.itp *.top \#*

%/newbox.gro: %/processed.gro
	$(GMX) editconf -f $*/processed.gro -o $*/newbox.gro -c -d 1.0 -bt cubic

%/solv.gro: %/newbox.gro
	$(GMX) solvate -cp $< -cs spc216.gro -o $@ -p $*/topol.top

%/ions.tpr: %/solv.gro
	$(GMX) grompp -f ions.mdp -c $< -p $*/topol.top -o $*/ions.tpr -po $*/ions_mdout.mdp

#	echo 13 | $(GMX) genion -s ions.tpr -o 1AKI_solv_ions.gro -p topol.top -pname NA -nname CL -nn 8 
#	Group    13 (            SOL) has 36846 elements
# add enough NaCl to reach 100 mM salt concentration
# http://ringo.ams.sunysb.edu/index.php/MD_Simulation:_Protein_in_Water
%/solv_ions.gro: %/ions.tpr
	echo 13 | $(GMX) genion -s $*/ions.tpr -p $*/topol.top -o $*/solv_ions.gro -pname NA -pq 1 -nname CL -nq -1 -conc $(word 3,$(subst /, ,$*)) -neutral

%/em.gro: %/solv_ions.gro
	$(GMX) grompp -f minim.mdp -c $< -p $*/topol.top -o $*/em.tpr -po $*/minim_mdout.mdp
	$(MDRUN) -v -deffnm $*/em 

# convert plot to png
%.png: %.xvg
	gnuplot -e 'set datafile commentschars "#@&";set term png;set output "$@";plot "$<" using 1:2 with lines'

# plot potential nrg
%/potential.xvg: %/em.edr
	echo 10 0 | $(GMX) energy -f $*/em.edr -o $*/potential.xvg 
	#At the prompt, type "10 0" to select Potential (10); zero (0) terminates input.

%/nvt.tpr: %/em.gro
	$(GMX) grompp -f $*/nvt.mdp -c $< -p $*/topol.top -o $@ -po $*/nvt_mdout.mdp

# http://www.bevanlab.biochem.vt.edu/Pages/Personal/justin/gmx-tutorials/lysozyme/06_equil.html
%/nvt.cpt: %/nvt.tpr
	$(MDRUN) -v -deffnm $*/nvt 

# plot temperature
%/energy.xvg: %/nvt.edr
	echo 15 0 | $(GMX) energy -f $*/nvt.edr -o $*/energy.xvg 
	#Type "15 0" at the prompt to select the temperature of the system and exit.

%/npt.tpr: %/nvt.cpt 
	$(GMX) grompp -f $*/npt.mdp -c $*/nvt.gro -t $*/nvt.cpt -p $*/topol.top -o $*/npt.tpr

# http://www.bevanlab.biochem.vt.edu/Pages/Personal/justin/gmx-tutorials/lysozyme/07_equil2.html
%/npt.cpt: %/npt.tpr
	$(MDRUN) -v -deffnm $*/npt 

# plot pressure
%/pressure.xvg: %/npt.edr
	echo 16 0 | $(GMX) energy -f $*/npt.edr -o $*/pressure.xvg 
	#Type "16 0" at the prompt to select the pressure of the system and exit. 

# plot density
%/density.xvg: %/npt.edr
	echo 22 0 | $(GMX) energy -f $*/npt.edr -o $*/density.xvg

# production MD run
# http://www.bevanlab.biochem.vt.edu/Pages/Personal/justin/gmx-tutorials/lysozyme/08_MD.html
%/md_0_1.tpr: %/npt.cpt
	$(GMX) grompp -f $*/md.mdp -c $*/npt.gro -t $*/npt.cpt -p $*/topol.top -o $*/md_0_1.tpr
%/md_0_1.cpt: %/md_0_1.tpr
	$(MDRUN) -v -deffnm $*/md_0_1 

# http://www.gromacs.org/Documentation/How-tos/Doing_Restarts
%/md_0_1.restart: 
	ibrun mdrun_mpi -maxh 48 -v -s $*/md_0_1.tpr -cpi $*/md_0_1.cpt

%/md_0_1_noPBC.xtc:  %/md_0_1.cpt
	echo 0 | $(GMX) trjconv -s $*/md_0_1.tpr -f $*/md_0_1.xtc -o $*/md_0_1_noPBC.xtc -pbc mol -ur compact 
	#Select 0 ("System") for output.

%/gyrate.xvg: %/md_0_1_noPBC.xtc
	echo 0 | $(GMX) gyrate -s $*/md_0_1.tpr -f $*/md_0_1_noPBC.xtc -o $*/gyrate.xvg

###########################################################################
.SECONDEXPANSION:
#https://www.gnu.org/software/make/manual/html_node/Secondary-Expansion.html#Secondary-Expansion
###########################################################################
#https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html
############
#15: OPLS-AA/L all-atom force field (2001 aminoacid dihedrals)
#posre.itp topol.top 3i9v_processed.gro: 3i9v.pdb
%/processed.gro: $$(firstword $$(subst /, ,$$*)).pdb
	mkdir -p $*
	sed 's/TemplateTemperature/$(word 2,$(subst /, ,$*))/g' mdTemplate.mdp  >  $*/md.mdp 
	sed 's/TemplateTemperature/$(word 2,$(subst /, ,$*))/g' nptTemplate.mdp >  $*/npt.mdp
	sed 's/TemplateTemperature/$(word 2,$(subst /, ,$*))/g' nvtTemplate.mdp >  $*/nvt.mdp
	echo $(FORCEFIELDID)  | $(GMX) pdb2gmx -f $<   -o $@  -water spce -p  $*/topol.top -i  $*/posre.itp -missing

