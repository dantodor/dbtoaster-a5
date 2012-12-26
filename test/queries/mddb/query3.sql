INCLUDE 'test/queries/mddb/schemas.sql';

--
-- Single unified version of query 3.
--
select BondE.t,
       sum(BondE.e + AngleE.e + DihedralE.e
           + NonBondedE.vw_ij + NonBondedE.e_ij) as e
from 
( select P.t,
         sum(0.5 * B.bond_const *
             pow(vec_length(P.x-P2.x,P.y-P2.y,P.z-P2.z)-B.bond_length, 2)) as e
  from  Bonds B, AtomPositions P, AtomPositions P2
  where B.atom_id1 = P.atom_id
  and   B.atom_id2 = P2.atom_id
  and   P.t = P2.t
  group by P.t )
as BondE,
( select P.t,
         sum(pow(radians(1),2) * A.angle_const *
             pow(degrees(
                 vector_angle(P.x-P2.x,P.y-P2.y,P.z-P2.z,
                              P3.x-P2.x,P3.y-P2.y,P3.z-P2.z))
                 - A.angle, 2)) as e
  from Angles A, AtomPositions P, AtomPositions P2, AtomPositions P3
  where A.atom_id1 = P.atom_id
  and   A.atom_id2 = P2.atom_id
  and   A.atom_id3 = P3.atom_id
  and   P.t = P2.t and P.t = P3.t
  group by P.t )
as AngleE,
( select t, sum(force_const * (1 + cos(n * degrees(d_angle) - delta))) as e
  from
    (select P.t, force_const, n, delta,
            dihedral_angle(P.x,P.y,P.z,
                           P2.x,P2.y,P2.z,
                           P3.x,P3.y,P3.z,
                           P4.x,P4.y,P4.z) as d_angle 
     from Dihedrals D,
          AtomPositions P, AtomPositions P2, AtomPositions P3, AtomPositions P4,
          AtomMeta M,      AtomMeta M2,      AtomMeta M3,      AtomMeta M4
     where ((D.atom_id1 = M.atom_id  or M.atom_type  = 'X') and M.atom_id  = P.atom_id)
     and   ((D.atom_id2 = M2.atom_id or M2.atom_type = 'X') and M2.atom_id = P2.atom_id)
     and   ((D.atom_id3 = M3.atom_id or M3.atom_type = 'X') and M3.atom_id = P3.atom_id)
     and   ((D.atom_id4 = M4.atom_id or M4.atom_type = 'X') and M4.atom_id = P4.atom_id)
     and   P.t = P2.t and P.t = P3.t and P.t = P4.t) as R
  group by t )
as DihedralE,
( select R.t, sum((R.force_const * pow(radians(1),2))
                * pow((1.0 * degrees(R.d_angle) - R.delta),2)) as e
  from
    (select P.t, D.force_const, D.delta,
            dihedral_angle(P.x,P.y,P.z,
                           P2.x,P2.y,P2.z,
                           P3.x,P3.y,P3.z,
                           P4.x,P4.y,P4.z) as d_angle
     from ImproperDihedrals D,
          AtomPositions P, AtomPositions P2, AtomPositions P3, AtomPositions P4,
          AtomMeta M,      AtomMeta M2,      AtomMeta M3,      AtomMeta M4
     where ((D.atom_id1 = M.atom_id  or M.atom_type  = 'X') and M.atom_id  = P.atom_id)
     and   ((D.atom_id2 = M2.atom_id or M2.atom_type = 'X') and M2.atom_id = P2.atom_id)
     and   ((D.atom_id3 = M3.atom_id or M3.atom_type = 'X') and M3.atom_id = P3.atom_id)
     and   ((D.atom_id4 = M4.atom_id or M4.atom_type = 'X') and M4.atom_id = P4.atom_id)
     and   P.t = P2.t and P.t = P3.t and P.t = P4.t) as R
  group by R.t)
as ImproperE,
( select t, sum(vw_ij) as vw_ij, sum(e_ij) as e_ij from 
    (
    select t, atom_id1, atom_id2,
             eps_ij*(pow(rmin_ij/r_ij, 12)-2*pow(rmin_ij/r_ij, 6))  as vw_ij,
             q_ij/r_ij                                              as e_ij
      from
        (select P.t, NB1.atom_id                            as atom_id1,
                     NB2.atom_id                            as atom_id2,
                     sqrt(NB1.eps*NB2.eps)                  as eps_ij,
                     NB1.rmin+NB2.rmin                      as rmin_ij,
                     vec_length(P.x-P2.x,P.y-P2.y,P.z-P2.z) as r_ij,
                     NB1.charge * NB2.charge                as q_ij
         from NonBonded NB1,   NonBonded NB2,
              AtomPositions P, AtomPositions P2
         where NB1.atom_id = P.atom_id
         and   NB2.atom_id = P2.atom_id
         and   P.atom_id <> P2.atom_id
         and   P.t = P2.t
         and   vec_length(P.x-P2.x,P.y-P2.y,P.z-P2.z) <= 12

         -- Avoid non-bonded pairs that actually exist as a bond.
         and (
              not exists
                (select atom_id1 from Bonds B
                 where (B.atom_id1 = NB1.atom_id and B.atom_id2 = NB2.atom_id)
                    or (B.atom_id2 = NB1.atom_id and B.atom_id1 = NB2.atom_id))
             )

         -- We don't need to check 1-2 or 2-3 pairs since these are already
         -- checked above in the bonds.
         and (
              not exists
                (select atom_id1 from Angles A
                 where (A.atom_id1 = NB1.atom_id and A.atom_id3 = NB2.atom_id)
                    or (A.atom_id1 = NB2.atom_id and A.atom_id3 = NB1.atom_id))
             )
         ) as R 
    ) as NBPairs
  group by t
) as NonBondedE
where BondE.t = AngleE.t
and   BondE.t = DihedralE.t
and   BondE.t = NonBondedE.t
and   BondE.t = ImproperE.t
group by BondE.t;