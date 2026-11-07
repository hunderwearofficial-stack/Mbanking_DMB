class LoanModel {
  final String loanNumber;
  final String productName;
  final double plafon;
  final double remainingPrincipal;
  final double monthlyInstallment;
  final String nextDueDate;
  final int remainingTenorMonths;
  final int totalTenorMonths;
  final String interestRate;
  final String collectibilityStatus;
  final String collateral;
  final String branchOffice;

  const LoanModel({
    required this.loanNumber,
    required this.productName,
    required this.plafon,
    required this.remainingPrincipal,
    required this.monthlyInstallment,
    required this.nextDueDate,
    required this.remainingTenorMonths,
    required this.totalTenorMonths,
    required this.interestRate,
    required this.collectibilityStatus,
    required this.collateral,
    required this.branchOffice,
  });

  // Default demo loan for Bank DMB nasabah
  static const LoanModel demoLoan = LoanModel(
    loanNumber: 'PK-2026-DMB-0988',
    productName: 'Kredit Modal Kerja Mikro DMB',
    plafon: 50000000.0,
    remainingPrincipal: 35200000.0,
    monthlyInstallment: 1850000.0,
    nextDueDate: '15 November 2026',
    remainingTenorMonths: 22,
    totalTenorMonths: 36,
    interestRate: '1.15% flat/bln (13.8% p.a.)',
    collectibilityStatus: 'Kolektibilitas 1 (Lancar)',
    collateral: 'Sertifikat Hak Milik (SHM) No. 04882',
    branchOffice: 'KC Bogor Pajajaran (001)',
  );
}

