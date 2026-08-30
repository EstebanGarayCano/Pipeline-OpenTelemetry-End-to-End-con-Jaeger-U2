using Microsoft.EntityFrameworkCore;

namespace DataService.Data;

public class DataDbContext : DbContext
{
    public DataDbContext(DbContextOptions<DataDbContext> options) : base(options) { }

    public DbSet<DataRecord> DataRecords { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<DataRecord>().ToTable("data_records");
    }
}

public class DataRecord
{
    public int Id { get; set; }
    public string Key { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public string TraceId { get; set; } = string.Empty;
}
