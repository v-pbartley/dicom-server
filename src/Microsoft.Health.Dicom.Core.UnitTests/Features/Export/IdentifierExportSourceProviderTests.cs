﻿// -------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
// -------------------------------------------------------------------------------------------------

using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Health.Dicom.Core.Features.Export;
using Microsoft.Health.Dicom.Core.Features.Partition;
using Microsoft.Health.Dicom.Core.Features.Retrieve;
using Microsoft.Health.Dicom.Core.Models.Common;
using Microsoft.Health.Dicom.Core.Models.Export;
using NSubstitute;
using Xunit;

namespace Microsoft.Health.Dicom.Core.UnitTests.Features.Export;

public class IdentifierExportSourceProviderTests
{
    private readonly IServiceProvider _serviceProvider;
    private readonly IdentifierExportSourceProvider _provider;

    public IdentifierExportSourceProviderTests()
    {
        var services = new ServiceCollection();
        services.AddScoped(p => Substitute.For<IInstanceStore>());
        _serviceProvider = services.BuildServiceProvider();
        _provider = new IdentifierExportSourceProvider();
    }

    [Fact]
    public async Task GivenConfig_WhenCreatingSource_ThenReturnSource()
    {
        var options = new IdentifierExportOptions
        {
            Values = new DicomIdentifier[]
            {
                DicomIdentifier.ForInstance("1.2", "3.4.5", "6.7.8.10"),
                DicomIdentifier.ForSeries("11.12.13", "14"),
                DicomIdentifier.ForStudy("1516.17"),
            },
        };

        IExportSource source = await _provider.CreateAsync(_serviceProvider, options, PartitionEntry.Default);
        Assert.IsType<IdentifierExportSource>(source);
    }

    [Fact]
    public async Task GivenValidConfig_WhenValidating_ThenPass()
    {
        var options = new IdentifierExportOptions
        {
            Values = new DicomIdentifier[]
            {
                DicomIdentifier.ForInstance("1.2", "3.4.5", "6.7.8.10"),
                DicomIdentifier.ForSeries("11.12.13", "14"),
                DicomIdentifier.ForStudy("1516.17"),
            },
        };

        await _provider.ValidateAsync(options);
    }
}
